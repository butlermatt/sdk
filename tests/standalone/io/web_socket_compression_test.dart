// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
//
// VMOptions=
// VMOptions=--short_socket_read
// VMOptions=--short_socket_write
// VMOptions=--short_socket_read --short_socket_write

import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:async_helper/async_helper.dart";
import "package:crypto/crypto.dart";
import "package:expect/expect.dart";
import "package:path/path.dart";

const String HOST_NAME = 'localhost';

class SecurityConfiguration {
  final bool secure;

  SecurityConfiguration({bool this.secure});

  Future<HttpServer> createServer({int backlog: 0}) =>
      secure ? HttpServer.bindSecure(HOST_NAME,
          0,
          serverContext,
          backlog: backlog)
          : HttpServer.bind(HOST_NAME,
          0,
          backlog: backlog);

  Future<WebSocket> createClient(int port) =>
      // TODO(whesse): Add client context argument to WebSocket.connect
      WebSocket.connect('${secure ? "wss" : "ws"}://$HOST_NAME:$port/');

  void testCompressionSupport({server: false,
        client: false,
        contextTakeover: false}) {
    asyncStart();

    var clientOptions = new CompressionOptions(
        enabled: client,
        serverNoContextTakeover: contextTakeover,
        clientNoContextTakeover: contextTakeover);
    var serverOptions = new CompressionOptions(
        enabled: server,
        serverNoContextTakeover: contextTakeover,
        clientNoContextTakeover: contextTakeover);

    createServer().then((server) {
      server.listen((request) {
        Expect.isTrue(WebSocketTransformer.isUpgradeRequest(request));
        WebSocketTransformer.upgrade(request, compression: serverOptions)
                            .then((webSocket) {
            webSocket.listen((message) {
              Expect.equals("Hello World", message);

              webSocket.add(message);
              webSocket.close();
            });
            webSocket.add("Hello World");
        });
      });

      var url = '${secure ? "wss" : "ws"}://$HOST_NAME:${server.port}/';
      WebSocket.connect(url, compression: clientOptions).then((websocket) {
        var future = websocket.listen((message) {
          Expect.equals("Hello World", message);
        }).asFuture();
        websocket.add("Hello World");
        return future;
      }).then((_) {
        server.close();
        asyncEnd();
      });
    });
  }

  void runTests() {
    // No compression or takeover
    testCompressionSupport();
    // compression no takeover
    testCompressionSupport(server: true, client: true);
    // compression and context takeover.
    testCompressionSupport(server: true, client: true, contextTakeover: true);
    // Compression on client but not server. No take over
    testCompressionSupport(client: true);
    // Compression on server but not client.
    testCompressionSupport(server: true);
  }
}

main() {
  new SecurityConfiguration(secure: false).runTests();
  // TODO(whesse): Make WebSocket.connect() take an optional context: parameter.
  // new SecurityConfiguration(secure: true).runTests();
}
