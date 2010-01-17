#
# Archive your Twitter Saved Searches
# not very smart right now -- you'll need to do a lot of massaging afterwards
# ...but at least it's saving them
#
# Jamie Wilkinson <http://jamiedubs.com>
# http://github.com/jamiew
#
require 'rubygems'
require 'mechanize' #could just use open-uri to minimize dependencies, not using any mechanize fanciness
require 'json' #rather than XML -- again
require 'cgi' #for URL encoding -- we need a standalone lib for this, requireing all of CGI is stupid; TODO

config = YAML.load(File.open('config.yml'))
raise "No config.yml file! Aborting" if config.nil?
raise "Need user, password, and frequency in config.yml" unless config['user'] && config['pass'] && config['frequency']

# Initialize process by fetching our saved searches
# TODO: these could be cached, say, daily
searches_url = "http://twitter.com/saved_searches.json"
puts "Fetching #{searches_url} ..."
agent = WWW::Mechanize.new
agent.auth(config['user'], config['pass'])
agent.get(searches_url)
searches = JSON.parse(agent.page.body)

# Stores since_ids for successive runs 
refresh_urls = {}

# Run forever -- TODO use daemontools
while true do
  
  puts "Archiving saved searches @ #{Time.now.inspect}"

  # Process each search -- run it, save all results to a directory
  searches.each_with_index do |search, i|  
    print "Search #{i}, id=#{search['id']}, query=#{search['query']}"; STDOUT.flush

    #TODO: if we're getting the first page, also recurse backwards

    # Get the first page, or continue where we left off if we have a refresh_url
    q = CGI.escape(search['query'])
    params = refresh_urls[search['id']] ? refresh_urls[search['id']] : "?q=#{q}"

    agent.get("http://search.twitter.com/search.json#{params}")
    response = JSON.parse(agent.page.body)
    puts "Empty/error response from Twitter, skipping." and next if response.nil? || response.empty?  

    # Parse each tweet for fun.
    # puts "response=#{tweets.reject { |k,v| k == 'results'}.inspect}"
    tweets = response['results']
    puts "\t=>\tsince_id=#{response['since_id']}, #{tweets.length rescue nil} tweets"; STDOUT.flush
    puts "No tweets, skipping." and next if tweets.nil? || tweets.empty?    
  
    # stash our refresh URL for next round
    refresh_urls[search['id']] = response['refresh_url']
  
    # save the whole tweet doc to a directory w/ this search's raw ID
    # also using full (unsanitized) query for semanticness
    dir = File.expand_path(File.dirname(__FILE__))+"/searches/#{search['id']}_#{search['query']}"
    # file_id = Time.now.to_i #Unixtime
    file_id = response['since_id']
    filename = "#{dir}/#{file_id}.json"
    
    if File.exists?(filename)
      puts "File #{filename.inspect} already exists, not saving again."
    else  
      FileUtils.mkdir_p(dir) #Don't fail if it already exists
      puts "Saving tweets to #{filename}"
      tweets.each { |tweet|
        puts "  #{tweet['from_user']}: #{tweet['text']} (#{tweet['created_at']})"
      }
      agent.page.save_as(filename)
    end
  
  end
  
  # Snooze between runs.
  puts "Sleeping for #{config['frequency']} seconds..."
  sleep config['frequency']
  
end

exit 0

