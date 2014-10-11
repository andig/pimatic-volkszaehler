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
      uuid:
        description: "Channel UUID"
        type: "string"
  }
}