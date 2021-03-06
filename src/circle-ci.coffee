# Description:
#   Get status and control CircleCI from hubot
#
# Dependencies:
#   None
#
# Commands:
#   hubot circle me <user>/<repo> [branch] - Returns the build status of https://circleci.com/<user>/<repo>
#   hubot circle last <user>/<repo> [branch] - Returns the build status of the last complete build of https://circleci.com/<user>/<repo>
#   hubot circle retry <user>/<repo> <build_num> - Retries the build
#   hubot circle retry all <failed>/<success> - Retries all builds matching the provided status
#   hubot circle qa <user>/<repo> <branch> - Trigger deploy beta on a branch for QA purposes only
#   hubot circle deploy <user>/<repo> <branch> - Trigger deploy on a branch
#   hubot circle deploy-catalyst <user>/<repo> <branch> - Trigger `fastlane catalyst deploy` on a branch
#   hubot circle deploy-catalyst-legacy <user>/<repo> <branch> - Trigger `fastlane catalyst legacy` on a branch
#   hubot circle community <user>/<repo> <branch> [environment] - Trigger deploy community build on a branch
#   hubot circle pixeleraser <user>/<repo> <branch> [environment] - Trigger deploy pixeleraser build on a branch
#   hubot circle beta <user>/<repo> <branch> - Trigger deploy beta on a branch
#   hubot circle beta-catalyst <user>/<repo> <branch> - Trigger `fastlane catalyst appcenter` on a branch
#   hubot circle adhoc <user>/<repo> <branch> - Trigger adhoc build on a branch
#   hubot circle adhoc-catalyst <user>/<repo> <branch> - Trigger `fastlane catalyst adhoc` on a branch
#   hubot circle cancel <user>/<repo> <build_num> - Cancels the build
#   hubot circle clear <user>/<repo> - Clears the cache for the specified repo
#   hubot circle clear all - Clears the cache for the github organization set using HUBOT_GITHUB_ORG
#   hubot circle list <failed>/<success> - Lists all failed/success builds for a given project.
#   hubot circle pilot <email> <first_name> <last_name> <group> - Add a Testflight tester
#
# Configuration:
#   HUBOT_CIRCLECI_TOKEN
#   HUBOT_CIRCLECI_VCS_TYPE
#   HUBOT_GITHUB_ORG (optional)
#   HUBOT_CIRCLECI_HOST (optional. "circleci.com" is default.)
#
# Notes:
#   Set HUBOT_CIRCLECI_TOKEN with a valid API Token from CircleCI.
#   You can add an API token at https://circleci.com/account/api
#
# URLS:
#   POST /hubot/circle?room=<room>[&type=<type>]
#
# Author:
#   dylanlingelbach

url = require('url')
util = require('util')
querystring = require('querystring')

circleciHost = `process.env.HUBOT_CIRCLECI_HOST? process.env.HUBOT_CIRCLECI_HOST : "circleci.com"`
endpoint = "https://#{circleciHost}/api/v1.1"

toProject = (project) ->
  if project.indexOf("/") == -1 && process.env.HUBOT_GITHUB_ORG?
    return "#{process.env.HUBOT_GITHUB_ORG}/#{project}"
  else
    return project

toSha = (vcs_revision) ->
  vcs_revision.substring(0,7)

toDisplay = (status) ->
  status[0].toUpperCase() + status.slice(1)

formatBuildStatus = (build) ->
  "#{toDisplay(build.status)} in build #{build.build_num} of #{build.vcs_url} [#{build.branch}/#{toSha(build.vcs_revision)}] #{build.committer_name}: #{build.subject} - #{build.why}"

retryBuild = (msg, endpoint, project, build_num) ->
    msg.http("#{endpoint}/project/#{process.env.HUBOT_CIRCLECI_VCS_TYPE}/#{project}/#{build_num}/retry?circle-token=#{process.env.HUBOT_CIRCLECI_TOKEN}")
      .headers("Accept": "application/json")
      .post('{}') handleResponse msg, (response) ->
          msg.send "Retrying build #{build_num} of #{project} [#{response.branch}] with build #{response.build_num}"

getProjectsByStatus = (msg, endpoint, status, action) ->
    projects = []
    msg.http("#{endpoint}/projects?circle-token=#{process.env.HUBOT_CIRCLECI_TOKEN}")
      .headers("Accept": "application/json")
      .get() handleResponse msg, (response) ->
        for project in response
          build_branch = project.branches[project.default_branch]
          last_build = build_branch.recent_builds[0]
          if last_build.outcome is status
            projects.push project
        if action is 'list'
          listProjectsByStatus(msg, projects, status)
        else if action is 'retry'
          retryProjectsByStatus(msg, projects, status)

retryProjectsByStatus = (msg, projects, status) ->
    for project in projects
      build_branch = project.branches[project.default_branch]
      last_build = build_branch.recent_builds[0]
      project = toProject(project.reponame)
      retryBuild(msg, endpoint, project, last_build.build_num)

listProjectsByStatus = (msg, projects, status) ->
    if projects.length is 0
      msg.send "No projects match status #{status}"
    else
      message = "Projects where the last build's status is #{status}:\n"
      for project in projects
        build_branch = project.branches[project.default_branch]
        last_build = build_branch.recent_builds[0]
        message = message + "#{toDisplay(last_build.outcome)} in build https://circleci.com/gh/#{project.username}/#{project.reponame}/#{last_build.build_num} of #{project.vcs_url} [#{project.default_branch}]\n"
      msg.send "#{message}"

clearProjectCache = (msg, endpoint, project) ->
    msg.http("#{endpoint}/project/#{process.env.HUBOT_CIRCLECI_VCS_TYPE}/#{project}/build-cache?circle-token=#{process.env.HUBOT_CIRCLECI_TOKEN}")
      .headers("Accept": "application/json")
      .del('{}') handleResponse msg, (response) ->
          msg.send "Cleared build cache for #{project}"

clearAllProjectsCache = (msg, endpoint) ->
    msg.http("#{endpoint}/projects?circle-token=#{process.env.HUBOT_CIRCLECI_TOKEN}")
      .headers("Accept": "application/json")
      .get() handleResponse msg, (response) ->
        for project in response
          projectname = escape(toProject(project.reponame))
          clearProjectCache(msg, endpoint, projectname)

checkToken = (msg) ->
  unless process.env.HUBOT_CIRCLECI_TOKEN?
    msg.send 'You need to set HUBOT_CIRCLECI_TOKEN to a valid CircleCI API token'
    return false
  else
    return true

handleResponse = (msg, handler) ->
  (err, res, body) ->
    if err?
      msg.send "Something went really wrong: #{err}"

    try
      switch res.statusCode
        when 404
          response = JSON.parse(body)
          msg.send "I couldn't find what you were looking for: #{response.message}"
        when 401
          msg.send 'Not authorized.  Did you set HUBOT_CIRCLECI_TOKEN correctly?'
        when 500
          msg.send 'Yikes!  I turned that circle into a square (CircleCI responded 500)' # Don't send body since we'll get HTML back from Circle
        when 200, 201
          response = JSON.parse(body)
          handler response
        else
          msg.send "Hmm.  I don't know how to process that CircleCI response: #{res.statusCode}", body
    catch e
      msg.send "Something when wrong while parsing response: #{body}"

module.exports = (robot) ->

  robot.respond /circle me (\S*)\s*(\S*)/i, (msg) ->
    unless checkToken(msg)
      return
    project = escape(toProject(msg.match[1]))
    branch = if msg.match[2] then escape(msg.match[2]) else 'master'
    msg.http("#{endpoint}/project/#{process.env.HUBOT_CIRCLECI_VCS_TYPE}/#{project}/tree/#{branch}?circle-token=#{process.env.HUBOT_CIRCLECI_TOKEN}")
      .headers("Accept": "application/json")
      .get() handleResponse  msg, (response) ->
          if response.length == 0
            msg.send "Current status: #{project} [#{branch}]: unknown"
          else
            currentBuild = response[0]
            msg.send "Current status: #{formatBuildStatus(currentBuild)}"

  robot.respond /circle last (\S*)\s*(\S*)/i, (msg) ->
    unless checkToken(msg)
      return
    project = escape(toProject(msg.match[1]))
    branch = if msg.match[2] then escape(msg.match[2]) else 'master'
    msg.http("#{endpoint}/project/#{process.env.HUBOT_CIRCLECI_VCS_TYPE}/#{project}/tree/#{branch}?circle-token=#{process.env.HUBOT_CIRCLECI_TOKEN}")
      .headers("Accept": "application/json")
      .get() handleResponse msg, (response) ->
          if response.length == 0
            msg.send "Current status: #{project} [#{branch}]: unknown"
          else
            last = response[0]
            if last.status != 'running'
              msg.send "Current status: #{formatBuildStatus(last)}"
            else if last.previous && last.previous.status
              msg.send "Last status: #{formatBuildStatus(last)}"
            else
              msg.send "Last build status for #{project} [#{branch}]: unknown"

  robot.respond /circle retry (.*) (.*)/i, (msg) ->
    unless checkToken(msg)
      return
    if msg.match[1] is 'all'
      status = escape(msg.match[2])
      getProjectsByStatus(msg, endpoint, status, 'retry')
      return
    else
      project = escape(toProject(msg.match[1]))
    build_num = escape(msg.match[2])
    if build_num is 'last'
      branch = 'master'
      msg.http("#{endpoint}/project/#{process.env.HUBOT_CIRCLECI_VCS_TYPE}/#{project}/tree/#{branch}?circle-token=#{process.env.HUBOT_CIRCLECI_TOKEN}")
        .headers("Accept": "application/json")
        .get() handleResponse msg, (response) ->
            last = response[0]
            build_num = last.build_num
            retryBuild(msg, endpoint, project, build_num)
    else
      retryBuild(msg, endpoint, project, build_num)

  robot.respond /circle list (.*)/i, (msg) ->
    unless checkToken(msg)
      return
    status = escape(msg.match[1])
    unless status in ['failed', 'success']
      msg.send "Status can only be failed or success."
      return
    getProjectsByStatus(msg, endpoint, status, 'list')

  robot.respond /circle qa (\S*)\s*(\S*)/i, (msg) ->
    unless checkToken(msg)
      return
    project = escape(toProject(msg.match[1]))
    unless msg.match[2]?
      msg.send "I can't build without a branch"
      return
    branch = escape(msg.match[2])
    data = JSON.stringify({
      build_parameters:{ CIRCLE_JOB: 'deploy-beta', FASTLANE_LANE: 'public_beta', IOS_SWIFT_FLAGS: "-D QA_ENV" }
    })
    msg.http("#{endpoint}/project/#{process.env.HUBOT_CIRCLECI_VCS_TYPE}/#{project}/tree/#{branch}?circle-token=#{process.env.HUBOT_CIRCLECI_TOKEN}")
      .headers("Accept": "application/json")
      .headers("Content-Type": "application/json")
      .post(data) handleResponse msg, (response) ->
          msg.send "Build #{response.build_num} triggered: #{response.build_url}"

  robot.respond /circle deploy (\S*)\s*(\S*)/i, (msg) ->
    unless checkToken(msg)
      return
    project = escape(toProject(msg.match[1]))
    unless msg.match[2]?
      msg.send "I can't build without a branch"
      return
    branch = escape(msg.match[2])
    data = JSON.stringify({
      build_parameters:{ CIRCLE_JOB: 'deploy-beta' }
    })
    msg.http("#{endpoint}/project/#{process.env.HUBOT_CIRCLECI_VCS_TYPE}/#{project}/tree/#{branch}?circle-token=#{process.env.HUBOT_CIRCLECI_TOKEN}")
      .headers("Accept": "application/json")
      .headers("Content-Type": "application/json")
      .post(data) handleResponse msg, (response) ->
          msg.send "Build #{response.build_num} triggered: #{response.build_url}"

  robot.respond /circle beta (\S*)\s*(\S*)/i, (msg) ->
    unless checkToken(msg)
      return
    project = escape(toProject(msg.match[1]))
    unless msg.match[2]?
      msg.send "I can't build without a branch"
      return
    branch = escape(msg.match[2])
    data = JSON.stringify({
      build_parameters:{ CIRCLE_JOB: 'deploy-beta', FASTLANE_LANE: 'public_beta' }
    })
    msg.http("#{endpoint}/project/#{process.env.HUBOT_CIRCLECI_VCS_TYPE}/#{project}/tree/#{branch}?circle-token=#{process.env.HUBOT_CIRCLECI_TOKEN}")
      .headers("Accept": "application/json")
      .headers("Content-Type": "application/json")
      .post(data) handleResponse msg, (response) ->
          msg.send "Build #{response.build_num} triggered: #{response.build_url}"

  robot.respond /circle community (\S*)\s*(\S*)\s*(\S*)/i, (msg) ->
    unless checkToken(msg)
      return
    project = escape(toProject(msg.match[1]))
    unless msg.match[2]?
      msg.send "I can't build without a branch"
      return
    branch = escape(msg.match[2])
    environment = escape(msg.match[3] ? "production").toUpperCase()
    swift_flags = "-D COMMUNITY_ENV_#{environment}"
    console.log "circle community: project=#{project}, branch=#{branch}, env=#{environment}, flags=#{swift_flags}"

    data = JSON.stringify({
      build_parameters:{ CIRCLE_JOB: 'deploy-beta', FASTLANE_LANE: 'community_beta', IOS_MARKETING_VERSION: '5.9.0', IOS_SWIFT_FLAGS: swift_flags }
    })
    msg.http("#{endpoint}/project/#{process.env.HUBOT_CIRCLECI_VCS_TYPE}/#{project}/tree/#{branch}?circle-token=#{process.env.HUBOT_CIRCLECI_TOKEN}")
      .headers("Accept": "application/json")
      .headers("Content-Type": "application/json")
      .post(data) handleResponse msg, (response) ->
          msg.send "Build #{response.build_num} triggered: #{response.build_url}"

  robot.respond /circle pixeleraser (\S*)\s*(\S*)\s*(\S*)/i, (msg) ->
    unless checkToken(msg)
      return
    project = escape(toProject(msg.match[1]))
    unless msg.match[2]?
      msg.send "I can't build without a branch"
      return
    branch = escape(msg.match[2])
    environment = escape(msg.match[3] ? "production").toUpperCase()
    swift_flags = "-D PIXEL_ERASER_ENV_#{environment}"
    console.log "circle pixeleraser: project=#{project}, branch=#{branch}, env=#{environment}, flags=#{swift_flags}"

    data = JSON.stringify({
      build_parameters:{ CIRCLE_JOB: 'deploy-beta', FASTLANE_LANE: 'pixeleraser_beta', IOS_MARKETING_VERSION: '5.8.0', IOS_SWIFT_FLAGS: swift_flags }
    })
    msg.http("#{endpoint}/project/#{process.env.HUBOT_CIRCLECI_VCS_TYPE}/#{project}/tree/#{branch}?circle-token=#{process.env.HUBOT_CIRCLECI_TOKEN}")
      .headers("Accept": "application/json")
      .headers("Content-Type": "application/json")
      .post(data) handleResponse msg, (response) ->
          msg.send "Build #{response.build_num} triggered: #{response.build_url}"

  robot.respond /circle pilot (.*) (.*) (.*) (.*)/i, (msg) ->
    unless checkToken(msg)
      return
    project = "fastlane"
    branch = "master"
    unless msg.match[1]?
      msg.send "You must provide an email"
      return
    email = escape(msg.match[1])
    first = escape(msg.match[2] ? "")
    last = escape(msg.match[3] ? "")
    group = escape(msg.match[4] ? "External Testers")
    data = JSON.stringify({
      build_parameters:{ CIRCLE_JOB: 'add-tester', PILOT_GROUPS: group, PILOT_TESTER_EMAIL: email, PILOT_TESTER_FIRST_NAME: first, PILOT_TESTER_LAST_NAME: last }
    })
    msg.http("#{endpoint}/project/#{process.env.HUBOT_CIRCLECI_VCS_TYPE}/#{project}/tree/#{branch}?circle-token=#{process.env.HUBOT_CIRCLECI_TOKEN}")
      .headers("Accept": "application/json")
      .headers("Content-Type": "application/json")
      .post(data) handleResponse msg, (response) ->
          msg.send "Triggered add tester: #{email} (#{response.build_url})"

  robot.respond /circle adhoc (.*) (.*)/i, (msg) ->
    unless checkToken(msg)
      return
    project = escape(toProject(msg.match[1]))
    unless msg.match[2]?
      msg.send "I can't build without a branch"
      return
    branch = escape(msg.match[2])
    data = JSON.stringify({
      build_parameters:{ CIRCLE_JOB: 'deploy-beta', FASTLANE_LANE: 'adhoc' }
    })
    msg.http("#{endpoint}/project/#{process.env.HUBOT_CIRCLECI_VCS_TYPE}/#{project}/tree/#{branch}?circle-token=#{process.env.HUBOT_CIRCLECI_TOKEN}")
      .headers("Accept": "application/json")
      .headers("Content-Type": "application/json")
      .post(data) handleResponse msg, (response) ->
          msg.send "Build #{response.build_num} triggered: #{response.build_url}"

  robot.respond /circle adhoc-catalyst (.*) (.*)/i, (msg) ->
    unless checkToken(msg)
      return
    project = escape(toProject(msg.match[1]))
    unless msg.match[2]?
      msg.send "I can't build without a branch"
      return
    branch = escape(msg.match[2])
    data = JSON.stringify({
      build_parameters:{ CIRCLE_JOB: 'deploy-catalyst', FASTLANE_LANE: 'adhoc' }
    })
    msg.http("#{endpoint}/project/#{process.env.HUBOT_CIRCLECI_VCS_TYPE}/#{project}/tree/#{branch}?circle-token=#{process.env.HUBOT_CIRCLECI_TOKEN}")
      .headers("Accept": "application/json")
      .headers("Content-Type": "application/json")
      .post(data) handleResponse msg, (response) ->
          msg.send "Build #{response.build_num} triggered: #{response.build_url}"

  robot.respond /circle beta-catalyst (.*) (.*)/i, (msg) ->
    unless checkToken(msg)
      return
    project = escape(toProject(msg.match[1]))
    unless msg.match[2]?
      msg.send "I can't build without a branch"
      return
    branch = escape(msg.match[2])
    data = JSON.stringify({
      build_parameters:{ CIRCLE_JOB: 'deploy-catalyst', FASTLANE_LANE: 'appcenter' }
    })
    msg.http("#{endpoint}/project/#{process.env.HUBOT_CIRCLECI_VCS_TYPE}/#{project}/tree/#{branch}?circle-token=#{process.env.HUBOT_CIRCLECI_TOKEN}&")
      .headers("Accept": "application/json")
      .headers("Content-Type": "application/json")
      .post(data) handleResponse msg, (response) ->
          msg.send "Build #{response.build_num} triggered: #{response.build_url}"

  robot.respond /circle deploy-catalyst (.*) (.*)/i, (msg) ->
    unless checkToken(msg)
      return
    project = escape(toProject(msg.match[1]))
    unless msg.match[2]?
      msg.send "I can't build without a branch"
      return
    branch = escape(msg.match[2])
    data = JSON.stringify({
      build_parameters:{ CIRCLE_JOB: 'deploy-catalyst', FASTLANE_LANE: 'universal' }
    })
    msg.http("#{endpoint}/project/#{process.env.HUBOT_CIRCLECI_VCS_TYPE}/#{project}/tree/#{branch}?circle-token=#{process.env.HUBOT_CIRCLECI_TOKEN}&")
      .headers("Accept": "application/json")
      .headers("Content-Type": "application/json")
      .post(data) handleResponse msg, (response) ->
          msg.send "Build #{response.build_num} triggered: #{response.build_url}"

  robot.respond /circle deploy-catalyst-legacy (.*) (.*)/i, (msg) ->
    unless checkToken(msg)
      return
    project = escape(toProject(msg.match[1]))
    unless msg.match[2]?
      msg.send "I can't build without a branch"
      return
    branch = escape(msg.match[2])
    data = JSON.stringify({
      build_parameters:{ CIRCLE_JOB: 'deploy-catalyst-legacy', FASTLANE_LANE: 'legacy' }
    })
    msg.http("#{endpoint}/project/#{process.env.HUBOT_CIRCLECI_VCS_TYPE}/#{project}/tree/#{branch}?circle-token=#{process.env.HUBOT_CIRCLECI_TOKEN}")
      .headers("Accept": "application/json")
      .headers("Content-Type": "application/json")
      .post(data) handleResponse msg, (response) ->
          msg.send "Build #{response.build_num} triggered: #{response.build_url}"

  robot.respond /circle cancel (.*) (.*)/i, (msg) ->
    unless checkToken(msg)
      return
    project = escape(toProject(msg.match[1]))
    unless msg.match[2]?
      msg.send "I can't cancel without a build number"
      return
    build_num = escape(msg.match[2])
    msg.http("#{endpoint}/project/#{process.env.HUBOT_CIRCLECI_VCS_TYPE}/#{project}/#{build_num}/cancel?circle-token=#{process.env.HUBOT_CIRCLECI_TOKEN}")
      .headers("Accept": "application/json")
      .post('{}') handleResponse msg, (response) ->
          msg.send "Canceled build #{response.build_num} for #{project} [#{response.branch}]"

  robot.respond /circle clear (.*)/i, (msg) ->
    unless checkToken(msg)
      return
    if msg.match[1] is 'all'
      clearAllProjectsCache(msg, endpoint)
    else
      project = escape(toProject(msg.match[1]))
      clearProjectCache(msg, endpoint, project)

  robot.router.post "/hubot/circle", (req, res) ->
    console.log "Received circle webhook callback"

    query = querystring.parse url.parse(req.url).query
    res.end JSON.stringify {
       received: true #some client have problems with an empty response
    }

    user = robot.brain.userForId 'broadcast'
    user.room = query.room if query.room
    user.type = query.type if query.type

    console.log "Received CircleCI payload: #{util.inspect(req.body.payload)}"

    try
      robot.send user, formatBuildStatus(req.body.payload)

      console.log "Sent CircleCI build status message"

    catch error
      console.log "circle hook error: #{error}. Payload: #{util.inspect(req.body.payload)}"
