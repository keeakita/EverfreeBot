#!/bin/env ruby
# encoding: utf-8

require 'thread'
require 'socket'
require 'net/http'
require 'date'
require 'open3'
require 'time'

Thread.abort_on_exception = true

#Config options go here
$dir = "/home/william/workspace/ruby/IRC Bot/"
$logdir = $dir
#$logdir = "/var/www/botlog"
$feed_server = "techdude300.usa.cc"
$feed_page = "/everfreerp/index.php/api/statuses/public_timeline.rss"
$server = "irc.esper.net"
$port = 6667
$channel = "#mytestchannel"
$nick = "LiBroBot" #End it with "Bot" for best results with greetings
$password = nil #set to nil if no password
$log = true
$greetings = ["\302\241Hola, yo soy $name, y os voy a ayudar hoy!",
  "My full name is Dr. Count Johannson III, but you can call me $name.",
  "The name's Bot. $name.",
  "With a name like $name, I have to be good!",
  "$name should $name $name.",
  "I'm $name and I approve this message.",
  "I'm Commander $name and this is my favorite channel in the server.",
  "$name is best pony!",
  "$name: now 20% cooler!",
  "You may call me $name. I am a regular magical unicorn."]
$responses = ["o3o", ":P", "Uhhh... what?", "XD", "Stop pinging me!", "^.^", "..."]
#Mail settings for errors
$mail_opts = {
  :from => 'root@techdude300.usa.cc',
  :to => 'techdude300@gmail.com',
  :subject => "#{$nick} crashed!"}

#Variables needed for asessing when to restart after failure
$error_time_arr = Array.new
$tries = 0

#Used to prevent threads from clashing
#All file and socket access must use this
$mutex =  Mutex.new

#Disconnect gracefully on SIGTERM
Signal.trap(0) {
  puts "Terminating..."
  begin
    $socket.print("QUIT :Caught SIGTERM!\r\n")
    exit
  rescue
    exit
  end
}

def main
  $start_time = Time.now
  $socket = TCPSocket.open($server, $port)
  $users = []
  $ignore_arr = []
  
  #Sends a raw message to the IRC server (appends \r\n for convenience)
  def send_raw(message)
    $mutex.synchronize() do
      $socket.print(message + "\r\n")
      puts "Sent: " + message
    end
  end
  
  #Sends a message (PRVIMSG) directly to a user
  def send_to_user(user, message)
    send_raw("PRIVMSG " + user + " :" + message)
  end
  
  #Sends a message (PRIVMSG) to a channel
  def send_to_channel(message)
    send_to_user($channel, message)
    log($nick + ": " + message)
  end

  #Log to a file (if configured)
  def log(message)
    if $log
      $mutex.synchronize do
        log_file = File.new($logdir + Date.today.strftime('%F') + ".txt", "a")
        log_file.puts(Time.now.strftime("[%m/%d/%y %H:%M:%S] ") + message)
        log_file.close
      end
    end
  end

  #Start our thread to check for site updates
  $spider = Thread.new {
    begin
      #Log to a file (if configured)
      def log(message)
        if $log
          log_file = File.new($logdir + Date.today.strftime('%F') + ".txt", "a")
          log_file.puts(Time.now.strftime("[%m/%d/%y %H:%M:%S] ") + message)
          log_file.close
        end
      end
     
      #Send post to the channel
      def send(post)
        #TODO: Find out why it might be nil
        unless post.index(":").nil? 
          #Selectively remove @tags to avoiding pinging
          temp_arr = []
          post.split(' ').each do |word|
            if word =~ /\A\@\w+/
              unless $ignore_arr.include?(word[1..-1])
                temp_arr.push(word)
              end
            else
              temp_arr.push(word)
            end
          end
          post = temp_arr.join(' ');

          puts post

          #Change the name to [n]ame to avoid pinging
          post_array = post.split(':')
          name = post_array[0]
          name = "[" + name[0] + "]" + name[1..-1]
          post_array[0] = name
          post = post_array.join(":")
          
          #Make sure we don't send giant posts
          #TODO: Make it break on whitespace
          if post.length > 60
            tmp = "New post by " + post[0..60] + "..."
          else
            tmp = "New post by " + post
          end

          #Send the post
          $mutex.synchronize() do
            $socket.print("PRIVMSG " + $channel + " :" + tmp + "\r\n")
            log($nick + ": " + tmp)
            puts tmp
          end
          sleep(1)
        end
      end

      #Arrays to hold the content from the current & last checks
      old = nil
      new = nil

      last_modified = nil;
      
      #Stop the thread and wait until we're connected to the channel
      #The thread will be started later in this script from the main thread
      Thread.stop

      #Fetch the new data and parse it
      while 1 do
        #Fetch the feed
        if last_modified.nil? then last_modified = Time.now end
        req = Net::HTTP.new($feed_server, 80)
        if !old
          #Force loading the page
          response = req.get($feed_page)
        else
          response = req.get($feed_page, { 'If-Modified-Since' => last_modified.httpdate } )
        end
        if response.code == "200"
          last_modified = Time.parse(response['last-modified'])
          xml = response.body.split("\n")
          new = []
          for x in 0..(xml.length - 1) do
            if xml[x].include?("<item>")
              new << Hash[:content => xml[x + 1].lstrip.rstrip[7..-9].gsub(/&quot;/, '"'), :time => DateTime.parse(xml[x + 3].lstrip.rstrip[9..-11]), :id => xml[x + 4].lstrip.rstrip[6..-8].split("/")[-1].to_i]
            end
          end
         
          #Check for new posts
          if old
            new.each do |entry|
              if old[0][:time] < entry[:time]
                send entry[:content]
              elsif old[0][:time] == entry[:time]
                if old[0][:id] < entry[:id]
                  send entry[:content]
                end
              end
            end
          end
          
          #The old array is now the same as the new
          old = new.dup
          
          #Check only every 5 seconds
          #Can be adjusted to save bandwith
        elsif response.code != "304"
          if response.code.to_i >= 400
            raise("HTTP error #{response.code}")
          else
            raise("Don't know how to handle HTTP #{response.code}")
          end
        end
        sleep(5)
      end
    #Log errors and disconnect gracefully
    rescue => e
      errorFile = File.new($dir + "error.txt", "a")
      errorFile.puts(Time.now.to_s)
      errorFile.puts(e.message)
      errorFile.puts(e.backtrace)
      errorFile.close
      $socket.print("PRIVMSG #{$channel} :I don't feel so well... (" + e.message + ")\r\n")
      puts e.message
      puts e.backtrace
      $socket.print("QUIT\r\n")
      $spider.exit
    end
  }

  #Load the ignore file. If it doesn't exist, create it.
  if File.exists? $dir + "ignore.txt"
    ignore_file = File.new($dir + "ignore.txt", "r")
    ignore_file.each { |line| $ignore_arr << line.rstrip }
    ignore_file.close
  else
    ignore_file = File.new($dir + "ignore.txt", "w")
    ignore_file.close
  end
  
  #If the spider is still running, fetch a message and process it
  while $spider.alive? && (message = $socket.gets) do
    
    puts message
    
    if message[0..5] == "PING :"
      send_raw("PONG :" + message[6..-1])
      next
    end
    
    #Break the message into parts
    msgarr = message.split(" ")
    from = msgarr[0]
    code = msgarr[1]
    if msgarr[2][0].chr == ":"
      to = nil
      text = String.new
      msgarr[2..-1].each do |part|
        text << " " + part
      end
      text = text[2..-1]
    else
      to = msgarr[2]
      text = String.new
      msgarr[3..-1].each do |part|
        text << " " + part
      end
      text = text[2..-1]
    end
    
    #strip colors
    text.gsub!(/\x03(?:\d{1,2}(?:,\d{1,2})?)?/, '') if text
    
    #Login when connected
    if text == "*** Found your hostname" || text == "*** Couldn't look up your hostname"
      send_raw("NICK " + $nick)
      send_raw("USER " + $nick + " " + $nick + " " + $nick + " :" + $nick)
      log("Connected")
    end
    
    #Connect to channel on end of MOTD
    if code == "376" then
      send_to_user("NickServ", "identify " + $password) if !$password.nil?
      send_raw("JOIN " + $channel)
    end
      
    
    #Get names in listing
    if code == "353" 
      $users = message.split(" ")
    end
    
    #Send first message after getting the name list
    if code == "366"
      log("Joined channel " + $channel)
      $spider.run if $spider.stop?
      send_to_channel($greetings[rand($greetings.length)].gsub(/\$name/, $nick) + " (Started in " + (Time.now - $start_time).to_s + " seconds.)")
    end
    
    #Only process messages sent to the current channel
    if to == $channel && code == "PRIVMSG"
      
      #Strip ACTIONS, they mess up logic
      if (text.start_with? "\x01ACTION") && (text.end_with? "\x01")
        log(from[1..-1].split("!")[0] + text[7..-2])
      else
        log(from[1..-1].split("!")[0] + ": " + text)
      end
      
      #Add user to the ignore list, or tell the user they've already been added
      if text.start_with? "!ignore "
        if $ignore_arr.index(text[8..-1].rstrip.lstrip).nil?
          $ignore_arr << text[8..-1].rstrip.lstrip
          ignore_file = File.new($dir + "ignore.txt", "a")
          ignore_file.puts(text[8..-1].rstrip.lstrip)
          ignore_file.close
          send_to_channel("Tags for #{text[8..-1]} will be removed.")
        else
          send_to_channel("Tags for #{text[8..-1]} are already being removed.")
        end
      end
      
      #Remove user from the ignore list, or tell the user they've already been removed
      if text.start_with? "!watch "
        if $ignore_arr.delete(text[7..-1].rstrip.lstrip)
          File.delete($dir + "ignore.txt")
          ignore_file = File.new($dir + "ignore.txt", "w")
          $ignore_arr.each { |entry| ignore_file.puts(entry)}
          ignore_file.close
          send_to_channel("Tags for #{text[7..-1]} are no longer being removed.")
        else
          send_to_channel("Tags for #{text[7..-1]} are already not being removed.")
        end
      end
      
      #Send a response when mentioned
      send_to_channel($responses[rand($responses.length)]) if text.downcase.include? $nick.downcase 
    end
    
    #Log various events
    if to == $channel && code == "JOIN"
      log(from[1..-1].split("!")[0] + " joined the channel.")
    end
    
    if to == $channel && code == "PART"
      log(from[1..-1].split("!")[0] + " left the channel.")
    end
    
    if code == "QUIT"
      log(from[1..-1].split("!")[0] + " disconnected.")
    end

    if code == "NICK"
      log(from[1..-1].split("!")[0] + " changed their name to #{text}.")
    end
  end
 
  #We'll never reach this point unless our spider died
  #Throw an error so the bot can restart itself
  raise("Update thread has stopped.")
#Catch any errors and handle them
rescue => e
  #Send an email
  stdin = Open3.popen3("sendmail -t #{$mail_opts[:to]}")[0]
  stdin.puts "From: #{$mail_opts[:from]}"
  stdin.puts "To: #{$mail_opts[:to]}"
  stdin.puts "Subject: #{$nick} has encountered an error!"
  stdin.puts
  stdin.puts "#{$nick} has encountered an error!\n\nHere are the error details:\n#{e.message}\n#{e.backtrace}\n\nPlease make sure the bot is still running."
  stdin.puts
  stdin.close
  #Save the error info to file and leave the server
  $mutex.synchronize() do
    errorFile = File.new($dir + "error.txt", "a")
    errorFile.puts(Time.now.to_s)
    errorFile.puts(e.message)
    errorFile.puts(e.backtrace)
    errorFile.close
    $socket.print("PRIVMSG #{$channel} :I don't feel so well... (" + e.message + ")\r\n")
    $socket.print("QUIT\r\n")
    log_file = File.new($logdir + Date.today.strftime('%F') + ".txt", "a")
    log_file.puts(Time.now.strftime("[%m/%d/%y %H:%M:%S] ") + "ERROR: " + e.message)
    log_file.close
  end
 
  #reconnect unless there have been to many reconnection attempts
  $error_time_arr << Time.now
  if $error_time_arr.length > 2
    if (7 * 60) > ($error_time_arr[2] - $error_time_arr[1])
      exit
    end
    $error_time_arr.shift
  end
  
  #Wait 30 seconds to retry - may solve network issues
  sleep(30)
  main
end

main

