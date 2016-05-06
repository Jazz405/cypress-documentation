require("../spec_helper")

_            = require("lodash")
os           = require("os")
path         = require("path")
uuid         = require("node-uuid")
socketIo     = require("@cypress/core-socket")
extension    = require("@cypress/core-extension")
Promise      = require("bluebird")
open         = require("#{root}lib/util/open")
config       = require("#{root}lib/config")
Socket       = require("#{root}lib/socket")
Server       = require("#{root}lib/server")
Watchers     = require("#{root}lib/watchers")
automation   = require("#{root}lib/automation")
Fixtures     = require("#{root}/spec/server/helpers/fixtures")

describe "lib/socket", ->
  beforeEach ->
    Fixtures.scaffold()

    @todosPath = Fixtures.projectPath("todos")
    @server    = Server(@todosPath)

    config.get(@todosPath).then (@cfg) =>

  afterEach ->
    Fixtures.remove()
    @server.close()

  context "integration", ->
    beforeEach (done) ->
      ## create a for realz socket.io connection
      ## so we can test server emit / client emit events
      @server.open(@todosPath, @cfg).then =>
        @options = {}
        @watchers = {}
        @server.startWebsockets(@watchers, @cfg, @options)
        @socket = @server._socket

        done = _.once(done)

        ## when our real client connects then we're done
        @socket.io.on "connection", (socket) ->
          done()

        {clientUrlDisplay, socketIoRoute} = @cfg

        @client = socketIo.client(clientUrlDisplay, {path: socketIoRoute})

    afterEach ->
      @client.disconnect()

    context "on(automation:request)", ->
      describe "#onAutomation", ->
        before ->
          global.chrome = {
            cookies: {
              set: ->
              getAll: ->
              remove: ->
            }
            runtime: {

            }
          }

        beforeEach (done) ->
          @socket.io.on "connection", (@extClient) =>
            @extClient.on "automation:connected", ->
              done()

          extension.connect(@cfg.clientUrlDisplay, @cfg.socketIoRoute, socketIo.client)

        afterEach ->
          @extClient.disconnect()

        after ->
          delete global.chrome

        it "does not return cypress namespace or socket io cookies", (done) ->
          @sandbox.stub(chrome.cookies, "getAll")
          .withArgs({domain: "localhost"})
          .yieldsAsync([
            {name: "foo", value: "f", path: "/", domain: "localhost", secure: true, httpOnly: true, expiry: 123, a: "a", b: "c"}
            {name: "bar", value: "b", path: "/", domain: "localhost", secure: false, httpOnly: false, expiry: 456, c: "a", d: "c"}
            {name: "__cypress.foo", value: "b", path: "/", domain: "localhost", secure: false, httpOnly: false, expiry: 456, c: "a", d: "c"}
            {name: "__cypress.bar", value: "b", path: "/", domain: "localhost", secure: false, httpOnly: false, expiry: 456, c: "a", d: "c"}
            {name: "__socket.io", value: "b", path: "/", domain: "localhost", secure: false, httpOnly: false, expiry: 456, c: "a", d: "c"}
          ])

          @client.emit "automation:request", "get:cookies", {domain: "localhost"}, (resp) ->
            expect(resp).to.deep.eq({
              response: [
                {name: "foo", value: "f", path: "/", domain: "localhost", secure: true, httpOnly: true, expiry: 123}
                {name: "bar", value: "b", path: "/", domain: "localhost", secure: false, httpOnly: false, expiry: 456}
              ]
            })
            done()

        it "does not clear any namespaced cookies", (done) ->
          @sandbox.stub(chrome.cookies, "getAll")
          .withArgs({name: "session"})
          .yieldsAsync([
            {name: "session", value: "key", path: "/", domain: "google.com", secure: true, httpOnly: true, expiry: 123, a: "a", b: "c"}
          ])

          @sandbox.stub(chrome.cookies, "remove")
          .withArgs({name: "session", url: "https://google.com/"})
          .yieldsAsync(
            {name: "session", url: "https://google.com/", storeId: "123"}
          )

          cookies = [
            {name: "session", value: "key", path: "/", domain: "google.com", secure: true, httpOnly: true, expiry: 123}
            {domain: "localhost", name: "__cypress.initial", value: true}
            {domain: "localhost", name: "__socket.io", value: "123abc"}
          ]

          @client.emit "automation:request", "clear:cookies", cookies, (resp) ->
            expect(resp).to.deep.eq({
              response: [
                {name: "session", value: "key", path: "/", domain: "google.com", secure: true, httpOnly: true, expiry: 123}
              ]
            })
            done()

        it "throws trying to clear namespaced cookie"

        it "throws trying to set a namespaced cookie"

        it "throws trying to get a namespaced cookie"

        it "throws when automation:response has an error in it"

        it "throws when no clients connected to automation", (done) ->
          @extClient.disconnect()

          @client.emit "automation:request", "get:cookies", {domain: "foo"}, (resp) ->
            expect(resp.__error).to.eq("Could not process 'get:cookies'. No automation servers connected.")
            done()

      describe "options.onAutomationRequest", ->
        beforeEach ->
          @oar = @options.onAutomationRequest = @sandbox.stub()

        it "calls onAutomationRequest with message and data", (done) ->
          @oar.withArgs("focus", {foo: "bar"}).resolves([])

          @client.emit "automation:request", "focus", {foo: "bar"}, (resp) ->
            expect(resp).to.deep.eq({response: []})
            done()

        it "calls callback with error on rejection", ->
          err = new Error("foo")

          @oar.withArgs("focus", {foo: "bar"}).rejects(err)

          @client.emit "automation:request", "focus", {foo: "bar"}, (resp) ->
            expect(resp).to.deep.eq({__error: err.message, __name: err.name, __stack: err.stack})
            done()

        it "does not return __cypress or __socket.io namespaced cookies", ->

        it "throws when onAutomationRequest rejects"


    context "on(open:finder)", ->
      beforeEach ->
        @sandbox.stub(open, "opn").resolves()

      it "calls opn with path + opts on darwin", (done) ->
        @sandbox.stub(os, "platform").returns("darwin")

        @client.emit "open:finder", @cfg.parentTestsFolder, =>
          expect(open.opn).to.be.calledWith(@cfg.parentTestsFolder, {args: "-R"})
          done()

      it "calls opn with path + no opts when not on darwin", (done) ->
        @sandbox.stub(os, "platform").returns("linux")

        @client.emit "open:finder", @cfg.parentTestsFolder, =>
          expect(open.opn).to.be.calledWith(@cfg.parentTestsFolder, {})
          done()

    context "on(is:new:project)", ->
      it "calls onNewProject with config + cb", (done) ->
        @options.onIsNewProject = @sandbox.stub().resolves(true)

        @client.emit "is:new:project", (ret) =>
          expect(ret).to.be.true
          done()

    context "on(watch:test:file)", ->
      it "calls socket#watchTestFileByPath with config, filePath, watchers", (done) ->
        watchers = {}

        @sandbox.stub(@socket, "watchTestFileByPath").yieldsAsync()

        @client.emit "watch:test:file", "path/to/file", =>
          expect(@socket.watchTestFileByPath).to.be.calledWith(@cfg, "path/to/file", watchers)
          done()

    context "on(app:connect)", ->
      it "calls options.onConnect with socketId and socket", (done) ->
        @options.onConnect = (socketId, socket) ->
          expect(socketId).to.eq("sid-123")
          expect(socket.connected).to.be.true
          done()

        @client.emit "app:connect", "sid-123"

    context "on(fixture)", ->
      it "calls socket#onFixture", (done) ->
        onFixture = @sandbox.stub(@socket, "onFixture").yieldsAsync("bar")

        @client.emit "fixture", "foo", (resp) =>
          expect(resp).to.eq("bar")

          ## ensure onFixture was called with those same arguments
          ## therefore we have verified the socket binding and
          ## the call into onFixture with the proper arguments
          expect(onFixture).to.be.calledWith(@cfg, "foo")
          done()

      it "returns the fixture object", ->
        cb = @sandbox.spy()

        @socket.onFixture(@cfg, "foo", cb).then ->
          expect(cb).to.be.calledWith [
            {"json": true}
          ]

      it "errors when fixtures fails", ->
        cb = @sandbox.spy()

        @socket.onFixture(@cfg, "invalid.exe", cb).then ->
          obj = cb.getCall(0).args[0]
          expect(obj).to.have.property("__error")
          expect(obj.__error).to.eq "Invalid fixture extension: '.exe'. Acceptable file extensions are: .json, .js, .coffee, .html, .txt, .png, .jpg, .jpeg, .gif, .tif, .tiff, .zip"

    context "on(request)", ->
      it "calls socket#onRequest", (done) ->
        onRequest = @sandbox.stub(@socket, "onRequest").yieldsAsync("bar")

        @client.emit "request", "foo", (resp) ->
          expect(resp).to.eq("bar")

          ## ensure onRequest was called with those same arguments
          ## therefore we have verified the socket binding and
          ## the call into onRequest with the proper arguments
          expect(onRequest).to.be.calledWith("foo")
          done()

      it "returns the request object", ->
        nock("http://localhost:8080")
          .get("/status.json")
          .reply(200, {status: "ok"})

        cb = @sandbox.spy()

        req = {
          url: "http://localhost:8080/status.json"
        }

        @socket.onRequest(req, cb).then ->
          expect(cb).to.be.calledWithMatch {
            status: 200
            body: {status: "ok"}
          }

      it "errors when request fails", ->
        nock.enableNetConnect()

        nock("http://localhost:8080")
          .get("/status.json")
          .reply(200, {status: "ok"})

        cb = @sandbox.spy()

        req = {
          url: "http://localhost:1111/foo"
        }

        @socket.onRequest(req, cb).then ->
          obj = cb.getCall(0).args[0]
          expect(obj).to.have.property("__error", "Error: connect ECONNREFUSED 127.0.0.1:1111")

  context "unit", ->
    beforeEach ->
      @mockClient = @sandbox.stub({
        on: ->
        emit: ->
      })

      @io = {
        of: @sandbox.stub().returns({on: ->})
        on: @sandbox.stub().withArgs("connection").yields(@mockClient)
        emit: @sandbox.stub()
        close: @sandbox.stub()
      }

      @sandbox.stub(Socket.prototype, "createIo").returns(@io)

      @server.startWebsockets({}, @cfg, {})
      @socket = @server._socket

    context "#close", ->
      beforeEach ->
        @server.startWebsockets({}, @cfg, {})
        @socket = @server._socket

      it "calls close on #io", ->
        @socket.close()
        expect(@socket.io.close).to.be.called

      it "does not error when io isnt defined", ->
        @socket.close()

    context "#watchTestFileByPath", ->
      beforeEach ->
        @socket.testsDir = Fixtures.project "todos/tests"
        @filePath        = @socket.testsDir + "/test1.js"
        @watchers        = Watchers()

      afterEach ->
        @watchers.close()

      it "returns undefined if config.watchForFileChanges is false", ->
        @cfg.watchForFileChanges = false
        cb = @sandbox.spy()
        @socket.watchTestFileByPath(@cfg, "integration/test1.js", @watchers, cb)
        expect(cb).to.be.calledOnce

      it "returns undefined if #testFilePath matches arguments", ->
        @socket.testFilePath = @filePath
        cb = @sandbox.spy()
        @socket.watchTestFileByPath(@cfg, "integration/test1.js", @watchers, cb)
        expect(cb).to.be.calledOnce

      it "closes existing watchedTestFile", ->
        remove = @sandbox.stub(@watchers, "remove")
        @socket.watchedTestFile = "test1.js"
        @socket.watchTestFileByPath(@cfg, "test1.js", @watchers).then ->
          expect(remove).to.be.calledWithMatch("test1.js")

      it "sets #testFilePath", ->
        @socket.watchTestFileByPath(@cfg, "integration/test1.js", @watchers).then =>
          expect(@socket.testFilePath).to.eq @filePath

      it "can normalizes leading slash", ->
        @socket.watchTestFileByPath(@cfg, "/integration/test1.js", @watchers).then =>
          expect(@socket.testFilePath).to.eq @filePath

      it "watches file by path", (done) ->
        socket = @socket

        ## chokidar may take 100ms to pick up the file changes
        ## so we just override onTestFileChange and whenever
        ## its invoked we finish the test
        onTestFileChange = @sandbox.stub @socket, "onTestFileChange", ->
          expect(@).to.eq(socket)
          done()

        @socket.watchTestFileByPath(@cfg, "integration/test2.coffee", @watchers)
        .then =>
          fs.writeFileAsync(@socket.testsDir + "/test2.coffee", "foooooooooo")

      describe "ids project", ->
        beforeEach ->
          @idsPath = Fixtures.projectPath("ids")
          @server  = Server(@idsPath)

          config.get(@idsPath).then (@idCfg) =>

        it "joins on integration test files", ->
          @socket.testsDir = @idCfg.integrationFolder

          cfg = {integrationFolder: @idCfg.integrationFolder}

          @socket.watchTestFileByPath(cfg, "integration/foo.coffee", @watchers)
          .then =>
            expect(@socket.testFilePath).to.eq path.join(@idCfg.integrationFolder, "foo.coffee")

        it "watches file by path for integration folder", (done) ->
          file = path.join(@idCfg.integrationFolder, "bar.js")

          @sandbox.stub @socket, "onTestFileChange", =>
            expect(@socket.onTestFileChange).to.be.calledWith(
              @idCfg.integrationFolder,
              "integration/bar.js",
              file
            )
            done()

          @socket.watchTestFileByPath(@idCfg, "integration/bar.js", @watchers)
          .then =>
            fs.writeFileAsync(file, "foooooooooo")

    context "#startListening", ->
      it "sets #testsDir", ->
        @cfg.integrationFolder = path.join(@todosPath, "does-not-exist")

        @socket.startListening(@server.getHttpServer(), {}, @cfg, {})
        expect(@socket.testsDir).to.eq @cfg.integrationFolder

      describe "watch:test:file", ->
        it "listens for watch:test:file event", ->
          @socket.startListening(@server.getHttpServer(), {}, @cfg, {})
          expect(@mockClient.on).to.be.calledWith("watch:test:file")

        it "passes filePath to #watchTestFileByPath", ->
          watchers = {}
          watchTestFileByPath = @sandbox.stub(@socket, "watchTestFileByPath")

          @mockClient.on.withArgs("watch:test:file").yields("foo/bar/baz")

          @socket.startListening(@server.getHttpServer(), watchers, @cfg, {})
          expect(watchTestFileByPath).to.be.calledWith @cfg, "foo/bar/baz", watchers

      describe "#onTestFileChange", ->
        beforeEach ->
          @sandbox.spy(fs, "statAsync")

        it "does not emit if not a js or coffee files", ->
          @socket.onTestFileChange(@cfg.integrationFolder, "foo/bar")
          expect(fs.statAsync).not.to.be.called

        it "does not emit if a tmp file", ->
          @socket.onTestFileChange(@cfg.integrationFolder, "foo/subl-123.js.tmp")
          expect(fs.statAsync).not.to.be.called

        it "calls statAsync on .js file", ->
          @socket.onTestFileChange(@cfg.integrationFolder, "original/path", "foo/bar.js").catch(->).then =>
            expect(fs.statAsync).to.be.calledWith("foo/bar.js")

        it "calls statAsync on .coffee file", ->
          @socket.onTestFileChange(@cfg.integrationFolder, "original/path", "foo/bar.coffee").then =>
            expect(fs.statAsync).to.be.calledWith("foo/bar.coffee")

        it "does not emit if stat throws", ->
          @socket.onTestFileChange(@cfg.integrationFolder, "original/path", "foo/bar.js").then =>
            expect(@io.emit).not.to.be.called

        it "emits 'test:changed' with original/path", ->
          p = Fixtures.project("todos") + "/tests/test1.js"
          @socket.onTestFileChange(@cfg.integrationFolder, "original/path", p).then =>
            expect(@io.emit).to.be.calledWith("test:changed", {file: "original/path"})
