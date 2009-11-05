require 'optparse'
require 'chatbot'
require 'pivotal_tracker'

options = {
  :channel => 'traktest',
  :full => 'Pivotal Tracker IRC bot',
  :nick => 'trakbot',
  :port => '6667',
  :server => 'irc.freenode.net',
  :logging => :warn
}

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on('-u', '--username USERNAME', 'Specify rifftrax.com username.') {|options[:username]|}
  opts.on('-w', '--password PASSWORD', 'Specify rifftrax.com password.') {|options[:password]|}
  opts.on('-c', '--channel NAME', 'Specify IRC channel to /join. (test)') {|options[:channel]|}
  opts.on('-f', '--full-name NICK', 'Specify the bot\'s IRC full name. (iRiff report bot)') {|options[:full]|}
  opts.on('-n', '--nick NICK', 'Specify the bot\'s IRC nick. (riffbot)') {|options[:nick]|}
  opts.on('-s', '--server HOST', 'Specify IRC server hostname. (irc.freenode.net)') {|options[:server]|}
  opts.on('-p', '--port NUMBER', Integer, 'Specify IRC port number. (6667)') {|options[:port]|}
  opts.on('-l', '--logging LEVEL', [:debug, :info, :warn, :error, :fatal], 'Logging level (debug, info, warn, error, fatal) (warn)') {|options[:logging]|}
  opts.on('-y', '--storage-file FILENAME', 'The file trakbot will use to store its state. (storage.yml)') {|options[:storage_file]|}

  #opts.on('-i', '--interval MINUTES', Integer, 'Number of minutes to sleep between checks (10)') do |interval|
    #fail "Interval minimum is 5 minutes." unless interval >= 5
    #options[:interval] = interval
  #end

  opts.on_tail('-h', '--help', 'Display this screen') {puts opts; exit}
end

optparse.parse!

class Trakbot < Chatbot
	HELP =<<EOT
trak help: this
EOT

  def initialize(options)
    super options[:nick], options[:server], options[:port], options[:full]
    @options = options

    @logger.level = eval "Logger::#{options[:logging].to_s.upcase}"

    # The channel to join.
    add_room('#' + options[:channel])

    # Here you can modify the trigger phrase
    add_actions({
      /^(trak.*help|\.\?)$/ => lambda {|e,m| HELP.each_line{|l| reply e, l}}
    })
  end
end

Trakbot.new(options).start
