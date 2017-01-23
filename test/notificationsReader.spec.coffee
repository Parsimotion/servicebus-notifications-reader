require("../test/helpers/mockedRedis")()
mockAzure = require("../test/helpers/mockedAzure")()
{ basicConfig, deadLetterConfig, filtersConfig, message, healthConfig } = require("../test/helpers/fixture")
DidLastRetry = require("../src/observers/didLastRetry")
DeadLetterSucceeded = require("../src/observers/deadLetterSucceeded")
should = require("should")
NotificationsReader = require("../src/notificationsReader")
Promise = require("bluebird")

reader = (config = basicConfig) => new NotificationsReader config
describe "NotificationsReader", ->

  beforeEach ->
    mockAzure.refreshSpies()

  describe "Reader", ->

    it "should have correct defaults", ->
      reader().config.should.eql
        app: "una-app"
        subscription: "una-subscription"
        topic: "un-topic"
        concurrency: 25,
        deadLetter: false,
        log: false,
        receiveBatchSize: 5,
        waitForMessageTime: 3000
        health: redis: {}

    it "should subscribe to dead letter", ->
      reader(deadLetterConfig).config.subscription
      .should.eql "una-subscription/$DeadLetterQueue"

    it "should create a subscription", ->
      reader()._createSubscription()
      .then =>
        mockAzure.spies.createSubscription
        .withArgs "un-topic","una-subscription"
        .calledOnce.should.eql true

    it "should add filter to subscription", ->
      reader(filtersConfig)._createSubscription()
      .then =>
        mockAzure.spies.deleteRule.calledOnce.should.eql true
        mockAzure.spies.createSubscription.calledOnce.should.eql true
        mockAzure.spies.createRule
        .withArgs "un-topic","una-subscription","un-filtro", { sqlExpressionFilter: 'un_filtro eq \'True\'' }
        .calledOnce.should.eql true

    it "should build a message", ->
      aMessage = un: "mensaje"
      reader()._buildMessage body: JSON.stringify aMessage
      .should.eql aMessage

    it "should return undefined if message is not valid json", ->
      should.not.exists reader()._buildMessage body: "esto no es jsonizable"

    it "should delete message if it finishes ok", ->
      assertAfterProcess {
        message
        process: Promise.resolve
        assertion: ->
          mockAzure.spies.deleteMessage
          .withArgs message
          .calledOnce.should.eql true

          mockAzure.spies.unlockMessage
          .withArgs message
          .called.should.eql false
      }

    it "should unlock message if it finishes with errors when it isn't dead letter", ->
      assertAfterProcess {
        message
        process: Promise.reject
        assertion: ->
          mockAzure.spies.unlockMessage
          .withArgs message
          .calledOnce.should.eql true
      }

    it "should not unlock message if it finishes with errors when it is dead letter", ->
      assertAfterProcess {
        message
        process: Promise.reject
        assertion: ->
          mockAzure.spies.unlockMessage
          .called.should.eql false
      }, reader deadLetterConfig

    describe "Health observers", ->
      it "when fully configured, should add health observers", ->
        redis = healthConfig.health.redis
        reader(healthConfig).observers.should.eql [ new DidLastRetry(redis), new DeadLetterSucceeded(redis)]
      it "when not fully configured, should not add health observers", ->
        reader().observers.should.eql [ ]


assertAfterProcess = ({ message, process, assertion }, aReader = reader()) ->
  aReader._buildQueueWith process
  aReader._process message
  aReader.toProcess.drain = assertion
