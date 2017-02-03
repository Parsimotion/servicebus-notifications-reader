mockAzure = require("../test/helpers/mockedAzure")
{ basicConfig } = require("../test/helpers/fixture")
DidLastRetry = require("../src/observers/didLastRetry")
DeadLetterSucceeded = require("../src/observers/deadLetterSucceeded")
should = require("should")
NotificationsReaderBuilder = require("../src/notificationsReader.builder")
Promise = require("bluebird")
_ = require("lodash")

builder = null

describe "NotificationsReaderBuilder", ->
  beforeEach ->
    builder = new NotificationsReaderBuilder()

  it "should throw if not fully configured", ->
    builder.build.should.throw()

  it "should build a notification reader with proper config", ->
    builder
    .withServiceBus basicConfig
    .build()._sbnotis[0]
    .config.should.eql
      subscription: 'una-subscription',
      topic: 'un-topic',
      app: 'una-app',
      connectionString: 'un-connection-string',
      concurrency: 25,
      waitForMessageTime: 3000,
      receiveBatchSize: 5,
      log: false,
      deadLetter: false


  describe "When health is requested", ->

    it "should add health observers if health fully configured", ->
      builder
      .withServiceBus basicConfig
      .withHealth
        host: "host"
        port: 6739
        auth: "asdf"
        db: 2
      .build()._sbnotis[0]
      .observers.forEach (observer) =>
        (observer instanceof DidLastRetry or
        observer instanceof DeadLetterSucceeded)
        .should.eql true

    it "should throw if health is not fully configured", ->
      builder
      .withServiceBus basicConfig
      .withHealth.should.throw()

    describe "With explicit activeFor call", ->
      it "should build reader with two sbnotis", ->
        sbnotis = builder
        .activeFor
          pending: true
          failed: true
        ._getSbnotis()
        sbnotis.should.have.length 2
        readsFromDeadLetter(sbnotis[0]).should.eql false
        readsFromDeadLetter(sbnotis[1]).should.eql true

      it "should build reader with only a regular sbnoti", ->
        sbnotis = builder
        .activeFor
          pending: true
        ._getSbnotis()
        sbnotis.should.have.length 1
        readsFromDeadLetter(sbnotis[0]).should.eql false

    
    describe "Without explicit activeFor call", ->
      it "should default to one regular sbnoti", ->
        sbnotis = builder._getSbnotis()
        sbnotis.should.have.length 1
        readsFromDeadLetter(sbnotis[0]).should.eql false

onlyOne = (sbnotis, {deadLetter}) -> 
        sbnotis.should.have.length 1
        readsFromDeadLetter(sbnotis[0]).should.eql deadLetter
readsFromDeadLetter = (sbnoti) -> sbnoti.config.deadLetter