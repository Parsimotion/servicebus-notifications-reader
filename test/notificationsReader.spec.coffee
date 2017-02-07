mockAzure = require("../test/helpers/mockedAzure")
ObserverStub =require("../test/helpers/observerStub")
_ = require("lodash")
should = require("should")
Promise = require("bluebird")
NotificationsReaderBuilder = require("../src/notificationsReader.builder")
nock = require("nock")
{ retryableMessage, redis, basicConfig, deadLetterConfig, filtersConfig, message } = require("../test/helpers/fixture")

deadLetterReader = (config = basicConfig) =>
  new NotificationsReaderBuilder()
  .withConfig config
  .fromDeadLetter()
  .build()._sbnotis[0]

reader = (config = basicConfig) =>
  new NotificationsReaderBuilder()
  .withConfig config
  .build()._sbnotis[0]

{ observer, readerWithStubbedObserver } = {}

describe "NotificationsReader", ->

  beforeEach ->
    mockAzure.refreshSpies()

  describe "Reader", ->

    it "should have correct defaults", ->
      reader().config.should.eql
        subscription: "una-subscription"
        connectionString: "un-connection-string"
        topic: "un-topic"
        concurrency: 25,
        deadLetter: false,
        log: false,
        receiveBatchSize: 5,
        waitForMessageTime: 3000

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

    it "should delete message if it finishes ok", (done) ->
      assertAfterProcess done, {
        message
        process: Promise.resolve
        assertion: ->
          mockAzure.spies.deleteMessage
          .withArgs message
          .calledOnce.should.eql true
      }

    it "should unlock message if it finishes with errors when it isn't dead letter", (done) ->
      assertAfterProcess done, {
        message
        process: Promise.reject
        assertion: ->
          mockAzure.spies.unlockMessage
          .withArgs message
          .calledOnce.should.eql true
      }

    it "should not unlock message if it finishes with errors when it is dead letter", (done)->
      assertAfterProcess done, {
        message
        process: Promise.reject
        assertion: ->

          mockAzure.spies.unlockMessage
          .called.should.eql false
      }, deadLetterReader()

    describe "Observers", ->
      beforeEach ->
        observer = new ObserverStub()
        readerWithStubbedObserver = do ->
          new NotificationsReaderBuilder()
          .withConfig basicConfig
          .withObservers observer
          .build()._sbnotis[0]

      it "should notify success to observers on message success", (done)->
        assertAfterProcess done, {
          message
          process: Promise.resolve
          assertion: ->
            observer.success.calledOnce.should.eql true
            observer.error.notCalled.should.eql true
        }, readerWithStubbedObserver

      it "should notify error to observers on message error", (done)->
        assertAfterProcess done, {
          message
          process: Promise.reject
          assertion: ->
            observer.error.calledOnce.should.eql true
            observer.success.notCalled.should.eql true
        }, readerWithStubbedObserver

    describe "Run and request", ->
      beforeEach ->
        nock.disableNetConnect()
        nock.enableNetConnect('127.0.0.1')

        observer = new ObserverStub()
        readerWithStubbedObserver = do ->
          new NotificationsReaderBuilder()
          .withConfig basicConfig
          .withObservers observer
          .build()._sbnotis[0]

      it "should make a post request", (done) ->
        shouldMakeRequest 'post', done

      it "should make a put request", (done) ->
        shouldMakeRequest 'put', done

      it "should fail if status code is >= 400 and not ignored", (done) ->
        uri = "http://un.endpoint.com"

        scopeEndpoint = nock uri
        .post "/", { un: 'json', CompanyId: 123, ResourceId: 456 }
        .reply 400, bad:'request'

        assertAfterProcess done, {
          message
          process:
            readerWithStubbedObserver.http.process (aMessage) =>
              { uri, body: aMessage }
            , 'post'
          assertion: ->
            scopeEndpoint.isDone().should.eql true
            observer.success.notCalled.should.eql true
            observer.error.calledOnce.should.eql true
        }, readerWithStubbedObserver

      it "should not fail if status code is >= 400 but ignored", (done) ->
        uri = "http://un.endpoint.com"

        scopeEndpoint = nock uri
        .post "/", { un: 'json', CompanyId: 123, ResourceId: 456 }
        .reply 400, bad:'request'

        assertAfterProcess done, {
          message
          process:
            readerWithStubbedObserver.http.process (aMessage) =>
              { uri, body: aMessage }
            , 'post', ignoredStatusCodes: [400]
          assertion: ->
            scopeEndpoint.isDone().should.eql true
            observer.error.notCalled.should.eql true
            observer.success.calledOnce.should.eql true
        }, readerWithStubbedObserver

shouldMakeRequest = (method, done) ->
  uri = "http://un.endpoint.com"
  aReader = reader()
  nocked = nock uri
  scopeEndpoint =
    nocked[method] "/", { un: 'json', CompanyId: 123, ResourceId: 456 }
    .reply 200, todo:'bien'

  assertAfterProcess done, {
    message
    process:
      aReader.http.process (aMessage) =>
        { uri, body: aMessage }
      , method
    assertion: -> scopeEndpoint.isDone().should.eql true
  }, aReader

assertAfterProcess = (done, { message, process, assertion }, aReader = reader()) ->
  aReader._buildQueueWith process
  aReader._process message
  aReader.toProcess.drain = ->
    setTimeout ->
      assertion()
      done()
    , 50
