require 'socket'
require 'thread'
require 'uri'

semaphore = Mutex.new
sharebox = "SGVyZSdzIHRvIHRoZSBjcmF6eSBvbmVzLgpUaGUgbWlzZml0cy4KVGhlIHJlYmVscy4KVGhlIHRyb3VibGVtYWtlcnMuClRoZSByb3VuZCBwZWdzIGluIHRoZSBzcXVhcmUgaG9sZXMuClRoZSBvbmVzIHdobyBzZWUgdGhpbmdzIGRpZmZlcmVudGx5LgpUaGV5J3JlIG5vdCBmb25kIG9mIHJ1bGVzLgpBbmQgdGhleSBoYXZlIG5vIHJlc3BlY3QgZm9yIHRoZSBzdGF0dXMgcXVvLgpZb3UgY2FuIHF1b3RlIHRoZW0sIGRpc2FncmVlIHdpdGggdGhlbSwgZ2xvcmlmeSBvciB2aWxpZnkgdGhlbS4KQWJvdXQgdGhlIG9ubHkgdGhpbmcgeW91IGNhbid0IGRvIGlzIGlnbm9yZSB0aGVtLgpCZWNhdXNlIHRoZXkgY2hhbmdlIHRoaW5ncy4KVGhleSBwdXNoIHRoZSBodW1hbiByYWNlIGZvcndhcmQuCldoaWxlIHNvbWUgc2VlIHRoZW0gYXMgdGhlIGNyYXp5IG9uZXMsIHdlIHNlZSBnZW5pdXMuCkJlY2F1c2UgdGhlIHBlb3BsZSB3aG8gYXJlIGNyYXp5IGVub3VnaCB0byB0aGluawp0aGV5IGNhbiBjaGFuZ2UgdGhlIHdvcmxkLCBhcmUgdGhlIG9uZXMgd2hvIGRvLgo="
sharebox_html = '
<html>
	<head>
		<script src="http://ajax.googleapis.com/ajax/libs/jquery/2.0.3/jquery.min.js"></script>
		<script>
			function utf8_to_b64( str ) {
			  return window.btoa(unescape(encodeURIComponent( str )));
			}

			function b64_to_utf8( str ) {
			  return decodeURIComponent(escape(window.atob( str )));
			}
		</script>
	</head>
	<body>
		<h1>It works!</h1>
		<p>This is the default web page for this server.</p>
		<p>The web server software is running but no content has been added, yet.</p>
		<textarea id="sharebox" rows="24" cols="80"></textarea>
		<br />
		<div id="target"></div>
		<br />
		<div id="mutexes"></div>
		<script>
			window.mutex = 0;
			window.needpush = 0;

			function tryPasting( str )
			{
				var result = b64_to_utf8(str);
				$("#sharebox").val(result);
			}

			function pushAndPaste( str )
			{
				if(window.mutex != 0) {
					return;
				}
				window.mutex = 1;
				var to_upload = utf8_to_b64(str);
				if(str == "__INIT__") to_upload = str;
				var pertain_needpush = window.needpush;
				if(window.needpush == 0) {
					to_upload = "__INIT__"
				} else {
					window.needpush = 0;
				}

				$("#target").html(to_upload);

				$.ajax({
					type: "POST",
					url: "gpClipboard",
					timeout: 2000,
					data: { "sharebox_post_board":to_upload },
					success: function(data) {
						if(window.mutex != -1) {
							tryPasting(data);
						}
						window.mutex = 0;
					},
					error: function (XMLHttpRequest, textStatus, errorThrown) {
						$("#target").html("error retrieving content");
						window.needpush = pertain_needpush;
						window.mutex = 0;
					}
				});
			}

			$(document).ready(function() {
				setInterval(function() {
					pushAndPaste($("#sharebox").val());
				}, 1000);

				$("#sharebox").on("input", function() {
					window.needpush = 1;
					if(window.mutex == 1) window.mutex = -1;
				});

			});

			$("#target").hide();
			pushAndPaste("__INIT__");
		</script>
	</body>
</html>
'

server = TCPServer.new('localhost', 2345)
loop do
  Thread.start(server.accept) do |socket|
    response = "Hello world\n"
    content_length = 0
    loop do
      request = socket.gets
      STDERR.puts request
      if(response == "Hello world\n")
        if(request.match(/gpClipboard/) == nil)
          response = sharebox_html
          break
        else
          response = ""
        end
      end

      if(request == "\r\n")
        break
      end
      
      if(request.match(/Content-Length:/) != nil)
        content_length = request.match(/(?<foo>\d+)/)["foo"].to_i
      end
    end
    
    if(content_length > 0)
      request = socket.read(content_length)
      STDERR.puts request
      board = request.match(/sharebox_post_board=(?<foo>.*)/)["foo"]
      board = URI.unescape(board)
      semaphore.synchronize {
        if(board == "__INIT__")
          STDERR.puts "INIT received"
        else
          sharebox = board
        end
        response = sharebox
      }
    end
    
    socket.print "HTTP/1.1 200 OK\r\n" +
      "Content-Type: text/html\r\n" +
      "Content-Length: #{response.bytesize}\r\n" +
      "Connection: close\r\n"
    socket.print "\r\n"
    socket.print response
    socket.close
  end
end
