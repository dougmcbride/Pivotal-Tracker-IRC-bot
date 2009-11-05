require 'rubygems'
gem 'Ruby-IRC'
require 'IRC'
require 'logger'

DEBUG = false

class Chatbot < IRC
  def initialize(*args)
    super

    @actions = {}
    @logger = Logger.new STDOUT
    @rooms = %w(test)

    IRCEvent.add_callback('endofmotd') {|e| @rooms.each {|r| add_channel(r)}}

    IRCEvent.add_callback('privmsg') do |event|
      @actions.each_pair do |match_exp, block|
	begin
	  @logger.debug "match_exp = #{match_exp}"
	  match_data = event.message.match match_exp
	  if match_data
	    @logger.info "MATCH #{match_exp}"
	    block.call event, match_data
	  end
	rescue
	  @logger.error "ERROR"
	  @logger.error $!
	end
      end
    end
  end

  def add_actions(action_hash)
    @actions.merge! action_hash
  end

  def add_room(room)
    @rooms.push room
  end

  def reply(event, msg)
    to = event.channel == nick ? event.from : event.channel

    if msg.sub! %r(^/me\s+), ''
      send_action to, msg
    else
      send_message to, msg
    end
  end

  def one_of(strings)
    strings[rand(strings.size)]
  end

  def debug(msg)
    puts msg if DEBUG
  end
end

class IRCEvent
end
