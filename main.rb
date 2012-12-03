#!/bin/env ruby
# encoding: utf-8

require 'thread'
require 'socket'
require 'net/http'
require 'date'
require 'open3'

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
  
$error_time_arr = Array.new
$tries = 0

$mutex =  Mutex.new

def main
  $start_time = Time.now
  $socket = TCPSocket.open($server, $port)
  $users = []
  $ignore_arr = []
  
  def send_raw(message)
    $mutex.synchronize() do
      $socket.print(message + "\r\n")
      puts "Sent: " + message
    end
  end
  
  def send_to_user(user, message)
    send_raw("PRIVMSG " + user + " :" + message)
  end
  
  def send_to_channel(message)
    send_to_user($channel, message)
    log($nick + ": " + message)
  end
  
  def terminate
    send_raw("PART " + $channel + " :terminated().")
    send_raw("QUIT :terminated().")
  end
  
  def log(message)
    if $log
      $mutex.synchronize do
        log_file = File.new($logdir + Date.today.strftime('%F') + ".txt", "a")
        log_file.puts(Time.now.strftime("[%m/%d/%y %H:%M:%S] ") + message)
        log_file.close
      end
    end
  end

  $spider = Thread.new {
      begin
        def log(message)
          if $log
            log_file = File.new($logdir + Date.today.strftime('%F') + ".txt", "a")
            log_file.puts(Time.now.strftime("[%m/%d/%y %H:%M:%S] ") + message)
            log_file.close
          end
        end
        
        def send(post)
          #TODO: Find out why it might be nil
          unless post.index(":").nil? || $ignore_arr.include?(post[0..post.index(":")-1])
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
            $mutex.synchronize() do
              $socket.print("PRIVMSG " + $channel + " :" + tmp + "\r\n")
              log($nick + ": " + tmp)
              puts tmp
            end
            sleep(1)
          end
        end

        old = nil
        new = nil
        
        Thread.stop
        while 1 do
          xml = Net::HTTP.get($feed_server, $feed_page).split("\n")
          new = []
          for x in 0..(xml.length - 1) do
            if xml[x].include?("<item>")
              new << Hash[:content => xml[x + 1].lstrip.rstrip[7..-9].gsub(/&quot;/, '"'), :time => DateTime.parse(xml[x + 3].lstrip.rstrip[9..-11]), :id => xml[x + 4].lstrip.rstrip[6..-8].split("/")[-1].to_i]
            end
          end
          
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
          
          old = new.dup
          
          #puts "sleeping for 10 seconds..."
          sleep(5)
        end
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
 
  if File.exists? $dir + "ignore.txt"
    ignore_file = File.new($dir + "ignore.txt", "r")
    ignore_file.each { |line| $ignore_arr << line.rstrip }
    ignore_file.close
  else
    ignore_file = File.new($dir + "ignore.txt", "w")
    ignore_file.close
  end
  
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
    
    if to == $channel && code == "PRIVMSG"
      
      if (text.start_with? "\x01ACTION") && (text.end_with? "\x01")
        log(from[1..-1].split("!")[0] + text[7..-2])
      else
        log(from[1..-1].split("!")[0] + ": " + text)
      end
      
      if text.start_with? "!ignore "
        if $ignore_arr.index(text[8..-1].rstrip.lstrip).nil?
          $ignore_arr << text[8..-1].rstrip.lstrip
          ignore_file = File.new($dir + "ignore.txt", "a")
          ignore_file.puts(text[8..-1].rstrip.lstrip)
          ignore_file.close
          send_to_channel("User " + text[8..-1] + "'s posts will be ignored.")
        else
          send_to_channel("User " + text[8..-1] + " is already being ignored.")
        end
      end
      
      if text.start_with? "!watch "
        if $ignore_arr.delete(text[7..-1].rstrip.lstrip)
          File.delete($dir + "ignore.txt")
          ignore_file = File.new($dir + "ignore.txt", "w")
          $ignore_arr.each { |entry| ignore_file.puts(entry)}
          ignore_file.close
          send_to_channel("User " + text[7..-1] + "'s posts are now being tracked.")
        else
          send_to_channel("User " + text[7..-1] + " is not being ignored.")
        end
      end
      
      send_to_channel($responses[rand($responses.length)]) if text.downcase.include? $nick.downcase 
    end
    
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
  
  raise("Update thread has stopped.")
rescue => e
  stdin = Open3.popen3("sendmail -t #{$mail_opts[:to]}")[0]
  stdin.puts "From: #{$mail_opts[:from]}"
  stdin.puts "To: #{$mail_opts[:to]}"
  stdin.puts "Subject: #{$nick} has encountered an error!"
  stdin.puts
  stdin.puts "#{$nick} has encountered an error!\n\nHere are the error details:\n#{e.message}\n#{e.backtrace}\n\nPlease make sure the bot is still running."
  stdin.puts
  stdin.close
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
  
  $error_time_arr << Time.now
  if $error_time_arr.length > 2
    if (7 * 60) > ($error_time_arr[2] - $error_time_arr[1])
      exit
    end
    $error_time_arr.shift
  end
  
  sleep(30)
  main
end

main

