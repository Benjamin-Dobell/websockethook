require 'sinatra'
require 'sinatra-websocket'
require 'json'
require 'haml'

set :server, 'thin'
set :sockets, {}

def register(ws, id)
  socket_info = {
    id: id,
    path: "/hook/#{id}"
  }
  settings.sockets[ws] ||= {}
  settings.sockets[ws][id] = socket_info
  message_data = {
    type: 'registered',
    data: socket_info
  }

  message = message_data.to_json
  puts "sending: #{message}"
  ws.send message
  socket_info
end

def unregister(ws, id)
end

get '/' do
  if !request.websocket?
    haml :index
  else
    warn "websocket initializing"
    request.websocket do |ws|
      ws.onopen do
        id = SecureRandom.hex(8)
        register(ws, id)
      end

      ws.onmessage do |message|
        puts "received: #{message}"
        data = JSON.parse(message)
        if data['type']=='register' && data['id']
          if /^[a-zA-Z0-9._-]+$/ === data['id']
            register(ws, data['id'].downcase)
          else
            ws.send({type:'error', message:'ID may only include alphanumeric characters, periods, underscores and hyphens'}.to_json)
          end
        elsif data['type']=='unregister' && data['id']
          unregister(ws, data['id'].downcase)
        else
          ws.send({type:'error', message:'No such command'}.to_json)
        end
      end

      ws.onclose do
        warn "websocket closed"
        settings.sockets.delete(ws)
      end
    end
  end
end

post '/hook/:id' do
  id = params[:id].downcase
  sockets = settings.sockets.select {|ws,hooks| hooks[id]}
  halt 404 unless sockets.count > 0

  ['splat','captures','id'].each {|k| params.delete k}

  message_data = {
    type: 'hook',
    id: id,
    data: params
  }
  message = message_data.to_json
  puts "sending: #{message}"
  sockets.keys.each { |ws| ws.send message }
  {}.to_json
end

Thread.new do
  ping_frequency = (ENV['PING_FREQUENCY'] || 30).to_i

  loop do
    sockets = settings.sockets.keys.clone

    sockets.each do |socket|
      socket.send({type:'ping'}.to_json)
    end

    sleep ping_frequency
  end
end
