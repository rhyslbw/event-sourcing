
class Space.eventSourcing extends Space.Module

  @publish this, 'Space.eventSourcing'

  @commitsCollection: null

  configuration: Space.getenv.multi({
    eventSourcing: {
      snapshotting: {
        enabled: ['SPACE_ES_SNAPSHOTTING_ENABLED', true, 'bool']
        frequency: ['SPACE_ES_SNAPSHOTTING_FREQUENCY', 10, 'int']
      },
      mongo: {
        connection: {}
      },
      commitProcessing: {
        timeout: ['SPACE_ES_COMMIT_PROCESSING_TIMEOUT', 600000, 'int']
      }
    }
  })

  requiredModules: ['Space.messaging']

  dependencies: {
    meteor: 'Meteor'
    mongo: 'Mongo'
    mongoInternals: 'MongoInternals'
  }

  singletons: [
    'Space.eventSourcing.CommitPublisher'
    'Space.eventSourcing.CommitStore'
    'Space.eventSourcing.Repository'
    'Space.eventSourcing.ProjectionRebuilder'
  ]

  onInitialize: ->
    @injector.map('Space.eventSourcing.Snapshotter').asSingleton() if @_isSnapshotting()
    @_setupMongoConfiguration()
    @_setupCommitsCollection()

  afterInitialize: ->
    @injector.create('Space.eventSourcing.Snapshotter') if @_isSnapshotting()
    @commitPublisher = @injector.get('Space.eventSourcing.CommitPublisher')

  onStart: ->
    @meteor.setTimeout(=>
      @commitPublisher.startPublishing()
    , 2000)

  onReset: ->
    @injector.get('Space.eventSourcing.Commits')?.remove {}
    @injector.get('Space.eventSourcing.Snapshots')?.remove {} if @_isSnapshotting()

  onStop: ->
    @commitPublisher.stopPublishing()

  _setupMongoConfiguration: ->
    @configuration.eventSourcing.mongo.connection = @_mongoConnection()

  _setupCommitsCollection: ->
    if Space.eventSourcing.commitsCollection?
      CommitsCollection = Space.eventSourcing.commitsCollection
    else
      commitsName = Space.getenv('SPACE_ES_COMMITS_COLLECTION_NAME', 'space_eventSourcing_commits')
      CommitsCollection = new @mongo.Collection commitsName, @_mongoConnection()
      CommitsCollection._ensureIndex { "sourceId": 1, "version": 1 }, unique: true
      CommitsCollection._ensureIndex { "receivers.appId": 1 }
      CommitsCollection._ensureIndex { "_id": 1, "receivers.appId": 1 }
      Space.eventSourcing.commitsCollection = CommitsCollection
    @injector.map('Space.eventSourcing.Commits').to CommitsCollection

  _mongoConnection: ->
    if @_externalMongo()
      if @_externalMongoNeedsOplog()
        driverOptions = { oplogUrl:  Space.getenv('SPACE_ES_COMMITS_MONGO_OPLOG_URL') }
      else
        driverOptions = {}
      mongoUrl = Space.getenv('SPACE_ES_COMMITS_MONGO_URL')
      return _driver: new @mongoInternals.RemoteCollectionDriver(mongoUrl, driverOptions)
    else
      return {}

  _externalMongo: ->
    true if Space.getenv('SPACE_ES_COMMITS_MONGO_URL', '').length > 0

  _externalMongoNeedsOplog: ->
    true if Space.getenv('SPACE_ES_COMMITS_MONGO_OPLOG_URL', '').length > 0

  _isSnapshotting: -> @configuration.eventSourcing.snapshotting.enabled
