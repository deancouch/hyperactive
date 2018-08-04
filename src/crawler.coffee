_           = require 'lodash'
async       = require 'async'
request     = require 'request'
templates   = require 'uri-templates'
linkFinder  = require './link_finder'
linkFilter  = require './link_filter'

getRequest = (options, callback) ->
  request.get options, (err, res, body) ->
    callback {
      status: res?.statusCode
      ok: (res?.statusCode / 100 | 0) is 2
      res: res
      body: body
    }

DEFAULT_CONFIG = ->
  url: null
  options:
    json: true
  templateValues: {}
  samplePercentage: 100
  getLinks: linkFinder.getLinks
  validate: -> true
  recover: -> false

localItFunction = null
config = DEFAULT_CONFIG()

exports.getLinks = (body) ->
  linkFilter.filter(config.getLinks(body), config.samplePercentage)

exports.setConfig = (userconfig) ->
  config = _.extend {}, DEFAULT_CONFIG(), userconfig

setIt = (it) ->
  localItFunction = it

createIt = (url, templateValues) =>
  localItFunction url, (done) =>
    getRequest(_.extend({url}, config.options), (res) ->
      exports.processResponse(url, res, templateValues, done)
    )

exports.createItWithResult = (url, err) ->
  localItFunction url, (done) ->
    done err

exports.processResponse = (parent, res, templateValues, done) =>
  if not res.ok
    err = "Bad status #{res.status} for url #{parent}" unless config.recover(res)
    return done(err)
  else
    try
      if not validate parent, res.body
        return done("Not a valid response: #{res.body}")
    catch err
      return done(err)

  describe "#{parent}", ->
    requests = _.map exports.getLinks(res.body), (link) ->
      (callback) ->
        linkFilter.processLink link
        url = expandUrl(link, templateValues)
        getRequest(_.extend({url}, config.options), (res) ->
          exports.processResponse url, res, templateValues, (err) ->
            callback null, {err, link: url}
        )

    async.parallel requests, (err, results) ->
      results.forEach (result) ->
        exports.createItWithResult result.link, result.err
      done()

expandUrl = (url, values) ->
  if _.isObject(values) and not _.isEmpty(values)
    templates(url).fillFromObject(values)
  else
    url

validate = (url, body) ->
  return config.validate(url, body)

exports.startCrawl = (config, it) ->
  exports.reset()
  setIt it if it
  exports.setConfig config
  expandedUrl = expandUrl(config.url, config.templateValues)
  linkFilter.processLink expandedUrl
  createIt expandedUrl, config.templateValues

exports.reset = ->
  linkFilter.reset()
  localItFunction = null
  config = DEFAULT_CONFIG()
