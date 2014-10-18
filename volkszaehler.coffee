# #Volkszaehler plugin

module.exports = (env) ->

  # Require the bluebird promise library
  Promise = env.require 'bluebird'

  # Require the [cassert library](https://github.com/rhoot/cassert).
  assert = env.require 'cassert'

  # Require the decl-api library
  t = env.require('decl-api').types

  # Require request
  request = require 'request-promise'

  # ###fail-safe request function with built-in retries
  requestWithRetry = (options, maxRetries, retryDelay, retry) ->
    # default
    maxRetries || (maxRetries = 3)
    retryDelay || (retryDelay = 1000)
    retry || (retry = 0)

    env.logger.debug "GET #{options.uri||options.url}"

    # httpGet returns a promise
    return (request options)
      .error (error) ->
        # fail after maxRetries
        if (++retry > maxRetries)
          env.logger.warn "Failed " + options.uri + " - giving up"
          throw error

        # wait some time and try again
        return (Promise.delay retryDelay)
          .then ->
            env.logger.warn "Retrying " + options.uri
            return requestWithRetry options, maxRetries, retryDelay, retry


  # ###VolkszaehlerPlugin class
  class VolkszaehlerPlugin extends env.plugins.Plugin

    # dictinary of device ids for uuid->device translation
    devices: {}

    # ####init()
    # The `init` function is called by the framework to ask your plugin to initialise.
    #
    # #####params:
    #  * `app` is the [express] instance the framework is using.
    #  * `framework` the framework itself
    #  * `config` the properties the user specified as config for your plugin in the `plugins`
    #     section of the config.json file
    #
    init: (app, @framework, @config) =>
      # get volkszaehler capability definition
      assert @config.middleware?

      # when assigning promises to variables make sure Promises are returned
      # when handling errors don't return rejected promises or the error will bubble up resulting in "unhandled errors"

      @_capabilities = requestWithRetry({ uri: @config.middleware + '/capabilities.json', json: true })
        .then (json) ->
          assert json?.capabilities?.definitions
          return json?.capabilities?.definitions
        .error (error) ->
          env.logger.error "Error getting capabilitites from middleware at #{error.options?.uri}: #{error.response?.statusCode}"
          return null

      @_capabilities
        .then () =>
          requestWithRetry({ uri: @config.middleware + '/entity.json', json: true })
            .then (json) ->
              assert json?.entities?
              env.logger.info "Public channel #{entity.uuid} #{entity.title} (#{entity.type})" for entity in json?.entities
            .error (error) ->
              env.logger.error "Error getting public channels from middleware at #{error.options?.uri}: #{error.response?.statusCode}"
              return null

      # register device type
      deviceConfigDef = require("./device-config-schema")
      @framework.deviceManager.registerDeviceClass("Volkszaehler", {
        configDef: deviceConfigDef.Volkszaehler,
        createCallback: (config) =>
          return new VolkszaehlerDevice(config, this)
      })

      # accept GET and POST
      app.get( '/volkszaehler/:uuid', (req, res) =>
        assert req.params.uuid

        timestamp = req.param 'timestamp'
        value = req.param 'value'
        if timestamp and value
          res.send 'OK'
          @updateRegisteredDevice req.params.uuid, parseFloat(timestamp), parseFloat(value)
        else
          res.status(400).send 'ERROR'
      ).post( '/volkszaehler/:uuid', (req, res) =>
        assert req.params.uuid

        hook = req.param 'hook'
        timestamp = hook?.timestamp
        value = hook?.value
        if timestamp and value
          res.send 'OK'
          @updateRegisteredDevice req.params.uuid, parseFloat(timestamp), parseFloat(value)
        else
          res.status(400).send 'ERROR'
      )

    # ####registerDevice()
    # `registerDevice` registeres the channel device with the volkszaehler plugin
    # this allows the plugin to update the device when it receives push notifications from
    # volkszaehler middleware
    #
    # #####params:
    #  * `id` deviceId by which it can be obtained from the deviceManager
    #  * `uuid` volkszaehler channel id
    #
    registerDevice: (id, uuid) =>
      if @devices[uuid]?
        throw new assert.AssertionError("duplicate channel uuid \"#{uuid}\"")
      @devices[uuid] = id

    # ####updateRegisteredDevice()
    # `updateRegisteredDevice` updates the device when push notifications are received from the
    # volkszaehler middleware
    #
    # #####params:
    #  * `uuid` volkszaehler channel id
    #  * `timestamp` update timestamp in ms (bigint)
    #  * `value` updated value (float)
    #
    updateRegisteredDevice: (uuid, timestamp, value) =>
      deviceId = @devices[uuid]
      @framework.deviceManager.getDeviceById(deviceId).update(timestamp, value) if deviceId

    # ####getCapabilitiesByType()
    # `getCapabilitiesByType` returns capability definition by entity type
    #
    # #####params:
    #  * `type` volkszaehler entity type, e.g. 'power'
    #
    getCapabilitiesByType: (type) =>
      @_capabilities
        .then (capabilities) ->
          result = entityCaps for entityCaps in capabilities.entities when entityCaps.name is type
          assert result
          return Promise.resolve result


  # ###VolkszaehlerDevice class
  # encapsulates a volkszahler channel
  class VolkszaehlerDevice extends env.devices.Sensor
    # attributes
    attributes:
      value:
        description: "Channel value"
        type: t.number

    # actions
    actions:
      update:
        params:
          timestamp:
            type: t.number
          value:
            type: t.number
        description: "Tuple updated"

    _timestamp = null
    _value = null

    # ####constructor()
    # Initialize device by reading entity definition from middleware
    #
    constructor: (@config, @plugin) ->
      # console.log "VolkszaehlerDevice"
      @name = config.name
      @id = config.id

      # inherit plugin properties if not defined on device level
      @middleware = config.middleware or plugin.config.middleware
      @mode = config.mode or plugin.config.mode
      @timeout = 1000 * (config.timeout or plugin.config.timeout)

      # register device for updates
      @plugin.registerDevice @id, config.uuid

      # link to middleware entity definition
      @config.xLink = @middleware + "/entity/#{@config.uuid}.json"

      # get entity definition
      @_definition = requestWithRetry({ uri: @config.xLink, json: true })
        .then (json) =>
          assert json?.entity
          return json?.entity
        .error (error) =>
          env.logger.error "Error getting entity definition from middleware at #{error.options?.uri} for #{@config.uuid}: #{error.response?.statusCode}"
          return null

      # get entity capabilities
      @_capabilities = @_definition
        .then (definition) =>
          return if definition then @plugin.getCapabilitiesByType definition.type else null

      # set relevant capabilities
      @_capabilities
        .then (capabilities) =>
          @attributes['value'].unit = capabilities?.unit

      # keep updating - pull mode only
      if @mode is "pull"
        @requestUpdate()
        setInterval( =>
          @requestUpdate()
        , @timeout
        )

      # complete constructur
      super()

    # poll device according to timeout
    requestUpdate: ->
      requestWithRetry({ uri: @middleware + "/data/#{@config.uuid}.json?from=now", json: true })
        .then (json) =>
          assert json?.data?.tuples?
          [timestamp, value, _] = json?.data?.tuples.pop()
          @_setTuple timestamp, value
        .error (error) ->
          env.logger.error "Error getting capabilitites from middleware at #{error.options?.uri}: #{error.response?.statusCode}"

    # ####getTimestamp()
    # Get timestamp of last update in ms
    #
    getTimestamp: -> Promise.resolve(@_timestamp)

    # ####getValue()
    # Get value of last update in defined unit
    #
    getValue: -> Promise.resolve(@_value)

    _setTuple: (timestamp, value) ->
      if @_timestamp is timestamp and @_value is value then return
      @_timestamp = timestamp
      @_value = value
      @emit "value", value

    # ####update()
    # Update timestamp/value
    #  * `timestamp` update timestamp in ms (bigint)
    #  * `value` updated value (float)
    #
    update: (timestamp, value) ->
      @_setTuple timestamp, value

  # ###Finally
  volkszaehlerPlugin = new VolkszaehlerPlugin
  return volkszaehlerPlugin
