module.exports = {
  title: "Volkszaehler"
  Volkszaehler: {
    title: "Volkszaehler channel"
    type: "object"
    extensions: ["xLink"]
    properties:
      middleware:
        description: "Middleware URL"
        type: "string"
        default: ""
      mode:
        description: "Connection mode for middleware"
        type: "string"
        enum: ["push", "pull", ""]
        default: ""
      timeout:
        description: "Polling interval for channel updates in seconds when mode == pull"
        type: "number"
        default: 0
      uuid:
        description: "Channel UUID"
        type: "string"
  }
}