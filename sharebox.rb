require 'socket'
require 'thread'
require 'uri'
require 'base64'
require 'securerandom'

$sharebox_version = "0.9.4"
$semaphore = Mutex.new
$fileSemaphore = Mutex.new
$sharebox = "SGVyZSdzIHRvIHRoZSBjcmF6eSBvbmVzLgpUaGUgbWlzZml0cy4KVGhlIHJlYmVscy4KVGhlIHRyb3VibGVtYWtlcnMuClRoZSByb3VuZCBwZWdzIGluIHRoZSBzcXVhcmUgaG9sZXMuClRoZSBvbmVzIHdobyBzZWUgdGhpbmdzIGRpZmZlcmVudGx5LgpUaGV5J3JlIG5vdCBmb25kIG9mIHJ1bGVzLgpBbmQgdGhleSBoYXZlIG5vIHJlc3BlY3QgZm9yIHRoZSBzdGF0dXMgcXVvLgpZb3UgY2FuIHF1b3RlIHRoZW0sIGRpc2FncmVlIHdpdGggdGhlbSwgZ2xvcmlmeSBvciB2aWxpZnkgdGhlbS4KQWJvdXQgdGhlIG9ubHkgdGhpbmcgeW91IGNhbid0IGRvIGlzIGlnbm9yZSB0aGVtLgpCZWNhdXNlIHRoZXkgY2hhbmdlIHRoaW5ncy4KVGhleSBwdXNoIHRoZSBodW1hbiByYWNlIGZvcndhcmQuCldoaWxlIHNvbWUgc2VlIHRoZW0gYXMgdGhlIGNyYXp5IG9uZXMsIHdlIHNlZSBnZW5pdXMuCkJlY2F1c2UgdGhlIHBlb3BsZSB3aG8gYXJlIGNyYXp5IGVub3VnaCB0byB0aGluawp0aGV5IGNhbiBjaGFuZ2UgdGhlIHdvcmxkLCBhcmUgdGhlIG9uZXMgd2hvIGRvLgo="
# included dropzone.js by dropzonejs.com
$fileName = "steve/ThinkDifferent.txt"
$fileContent = "Content-Type: text/plain\r\n\r\nHere's to the crazy ones.
The misfits.
The rebels.
The troublemakers.
The round pegs in the square holes.
The ones who see things differently.
They're not fond of rules.
And they have no respect for the status quo.
You can quote them, disagree with them, glorify or vilify them.
About the only thing you can't do is ignore them.
Because they change things.
They push the human race forward.
While some see them as the crazy ones, we see genius.
Because the people who are crazy enough to think
they can change the world, are the ones who do.
"

def closeWithHTML(socket, response)
  socket.print "HTTP/1.1 200 OK\r\n" +
    "Content-Type: text/html\r\n" +
    "Content-Length: #{response.bytesize}\r\n" +
    "Connection: close\r\n"
  socket.print "\r\n"
  socket.print response
  socket.close
end

def closeWithFile(socket, file_name)
  file_content = File.read(file_name)
  closeWithHTML(socket, file_content.gsub(/SHAREBOX_VERSION/, $sharebox_version))
end

def handleGPClipboard(socket, request)
  board = request.match(/sharebox_post_board=(?<foo>.*)/)["foo"]
  board = URI.unescape(board)
  response = ""
  $semaphore.synchronize {
    if(board == "__INIT__")
      STDERR.puts "INIT received"
    else
      $sharebox = board
    end
    response = $sharebox
  }
  closeWithHTML(socket, response)
end

def friendly_filename(filename)
  filename
  #.gsub(/[^\w\s\._-]+/, '')
  #.gsub(/(^|\b\s)\s+($|\s?\b)/, '\\1\\2')
  #.gsub(/\s+/, '_')
end

def handleGPFileUpload(socket, request, boundary)
  boundary = boundary[1..-2] # get rid of carriage returns
  STDERR.puts "BOUNDARY=" + boundary
  request_split = request.split("\r\n")
  file_content = ""
  file_name_match = request_split[1].match(/filename=\"(?<foo>.*)\"/)
  met = 0
  for i in 0..(request_split.size() - 1)
    if request_split[i].match(boundary) != nil
      met += 1
      break if met > 1
    elsif met == 1
      file_content += "\r\n" if file_content != ""
      file_content += request_split[i]
    end
  end
  
  file_name = "NONAME"
  file_name = file_name_match["foo"] if file_name_match != nil
  file_name = friendly_filename(file_name)
  file_name = SecureRandom.hex(3) + "/" + file_name
  STDERR.puts file_name
  #STDERR.puts file_content
  $fileSemaphore.synchronize {
    $fileName = file_name
    $fileContent = file_content
  }
  STDERR.puts "ENDBOUNDARY"
  socket.close
  GC.start
end

def handleFileDownload(socket, request_file)
  global_file_name = ""
  global_file_content = ""
  $fileSemaphore.synchronize {
    global_file_name = $fileName
    global_file_content = $fileContent
  }
  if(global_file_name == request_file)
    STDERR.puts "Download filename match"
    socket.print "HTTP/1.1 200 OK\r\n"
    socket.print global_file_content
    socket.close
  else
    STDERR.puts "Download filename not match"
    socket.print "HTTP/1.1 404 Not Found\r\n"
    socket.close
  end
end

port = 2345
port = ARGV[0].to_i if ARGV[0].to_i.to_s == ARGV[0]
server = TCPServer.new(port)
loop do
  Thread.start(server.accept) do |socket|
    first_line = 1
    content_length = 0
    request_type = 0 # 0 for html, 1 for gpClipboard, 2 for gpFileUpload, 3 for gpFileDownload, 4 for gpFilename, 5 for dropzone.min.js
    boundary = ""
    request_file = ""
    loop do
      request = socket.gets
      STDERR.puts request
      if(first_line == 1)
        first_line = 0
        request_type = 1 if(request.match(/gpClipboard/) != nil)
        request_type = 2 if(request.match(/gpFileUpload/) != nil)
        if(request.match(/gpFileDownload\/(?<foo>.*) /) != nil)
          request_type = 3
          request_file = request.match(/gpFileDownload\/(?<foo>.*) /)["foo"]
          request_file = URI.unescape(request_file)
          STDERR.puts "Got request '#{request_file}'"
        end
        request_type = 4 if(request.match(/gpFilename/) != nil)
        request_type = 5 if(request.match(/dropzone\.js/) != nil)
        request_type = 6 if(request.match(/jquery\.js/) != nil)
      end

      if(request == "\r\n")
        break
      end
      
      if(request.match(/Content-Length:/) != nil)
        content_length = request.match(/(?<foo>\d+)/)["foo"].to_i
      end
      if(request.match(/Content-Type.*boundary=/) != nil)
        boundary = request.match(/boundary=(?<foo>.*)/)["foo"]
      end
    end
    
    if(content_length > 0)
      request = socket.read(content_length)
      STDERR.puts request if(request_type != 2)
    end
    
    closeWithFile(socket, "index.html") if(request_type == 0)
    handleGPClipboard(socket, request) if(request_type == 1)
    handleGPFileUpload(socket, request, boundary) if(request_type == 2)
    handleFileDownload(socket, request_file) if(request_type == 3)
    closeWithHTML(socket, $fileName) if(request_type == 4)
    closeWithFile(socket, "dropzone.js") if(request_type == 5)
    closeWithFile(socket, "jquery.js") if(request_type == 6)
    
  end
end
