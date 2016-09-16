team_members = [
  'thilgen',
  'tmcinerney',
  'alduethadyn',
  'jwsf',
  'mariozaizar'
]

date_range = "2016-04-01..2016-09-30"

# generate an access token for your account that has the appropriate access
# https://help.github.com/articles/creating-an-access-token-for-command-line-use/

auth = {
  :username => "your git user name here",
  :password => "your access token here"
}

org_name = "zendesk"

###################################

require 'httparty'
require 'time_difference'

num_prs_commented = {}
num_prs_created = {}
num_prs_closed = {}
num_pr_comments = {}
pr_changes = {}

pr_with_most_comments = {
  'count'       => 0,
  'team_member' => "",
  'url'         => ""
}

pr_opened_the_longest = {
  'duration'    => 0,
  'team_member' => "",
  'url'         => ""
}

pr_opened_the_shortest = {
  'duration'    => -1,
  'team_member' => "",
  'url'         => ""
}

pr_average_duration = {
  'total_duration' => 0,
  'count'          => 0
}

pr_with_the_most_files = {
  'num_files'   => 0,
  'team_member' => "",
  'url'         => ""
}

pr_with_the_longest_body = {
  'body_length'   => 0,
  'team_member' => "",
  'url'         => ""
}

team_members.each do |team_member|
  result = HTTParty.get(
    "https://api.github.com/search/issues?q=org:#{org_name}+type:pr+commenter:#{team_member}+created:#{date_range}",
    :basic_auth => auth
  )
  num_prs_commented[team_member] = result['total_count'] # don't need to page results if we are just getting total_count
end

team_members.each do |team_member|
  result = HTTParty.get(
    "https://api.github.com/search/issues?q=org:#{org_name}+type:pr+author:#{team_member}+created:#{date_range}",
    :basic_auth => auth
  )
  num_prs_created[team_member] = result['total_count']  # don't need to page results if we are just getting total_count
end

def get_duration_str(seconds)
  if seconds > 60*60*24
    return (seconds/60/60/24).round(1).to_s + " (days)"
  elsif seconds > 60*60
    return (seconds/60/60).round(1).to_s + " (hours)"
  elsif seconds > 60
    return (seconds/60).round(1).to_s + " (mins)"
  else
    return seconds.round(1).to_s + " (secs)"
  end
end

def ignore_file(file_name)
  ignore_prefixes = [
    ".",
    "Gemfile",
    "vendor/",
    "Rakefile",
    "config/zuora/exports/"
  ]
  ignore_prefixes.each do |prefix|
    if 0 == file_name[0, prefix.length].casecmp(prefix)
      return true
    end
  end
  return false
end

def test_file(file_name)
  test_prefixes = [
    "spec/",
    "test/",
  ]
  test_prefixes.each do |prefix|
    if 0 == file_name[0, prefix.length].casecmp(prefix)
      return true
    end
  end
  return false
end

@test_additions = 0;
@test_deletions = 0;
@dev_additions = 0;
@dev_deletions = 0;

def get_pr_files(auth, pr_html_uri, pr_files_uri)
  file_count = 0
  uri = pr_files_uri + "/files"
  loop do
    result = HTTParty.get(uri, :basic_auth => auth) 
    file_count = file_count + result.size 
    result.each do |f|
      file_name = f['filename']
      if test_file file_name
        @test_additions = @test_additions + f['additions']
        @test_deletions = @test_deletions + f['deletions']
        file_type = "TEST"
      elsif ignore_file file_name
        # do nothing
        file_type = "IGNORE"
      else
        @dev_additions = @dev_additions + f['additions']
        @dev_deletions = @dev_deletions + f['deletions']
        file_type = "DEV"
      end
    end
    break if result.headers['link'].nil?
    uri = nil
    result.headers['link'].split(", ").each do |link_ref_line|
      link_ref_line.scan(/<(http.*page=(\d+)).*rel.*(last|next)/).each do |link_ref|
        if link_ref[2] == "next"
          uri = link_ref[0]
        end
      end
    end
    break if uri.nil?
  end
  return file_count
end

team_members.each do |team_member|
  @test_additions = 0;
  @test_deletions = 0;
  @dev_additions = 0;
  @dev_deletions = 0;
  @avg_total = 0;
  @avg_count = 0;
  uri = "https://api.github.com/search/issues?q=org:#{org_name}+type:pr+author:#{team_member}+created:#{date_range}+is:merged"
  loop do
    result = HTTParty.get(uri, :basic_auth => auth)
    num_prs_closed[team_member] = result['total_count']
    result['items'].each do |pr|
      pr_comments = pr['comments']
      pr_html_url = pr['html_url']
      pr_body_length = pr['body'].length      
      @avg_total = @avg_total + pr_body_length
      @avg_count = @avg_count + 1
      pr_created_at = pr['created_at']
      pr_closed_at = pr['closed_at']
      current_comment_count = num_pr_comments[team_member].nil? ? 0 : num_pr_comments[team_member]
      num_pr_comments[team_member] = current_comment_count + pr_comments
      if pr_comments > pr_with_most_comments['count']
        pr_with_most_comments['count'] = pr_comments
        pr_with_most_comments['team_member'] = team_member
        pr_with_most_comments['url'] = pr_html_url
      end
      duration = TimeDifference.between(DateTime.parse(pr_closed_at), DateTime.parse(pr_created_at)).in_seconds
      if duration > pr_opened_the_longest['duration']
        pr_opened_the_longest['duration'] = duration
        pr_opened_the_longest['team_member'] = team_member
        pr_opened_the_longest['url'] = pr_html_url
      end
      if ((duration < pr_opened_the_shortest['duration']) || (-1 == pr_opened_the_shortest['duration']))
        pr_opened_the_shortest['duration'] = duration
        pr_opened_the_shortest['team_member'] = team_member
        pr_opened_the_shortest['url'] = pr_html_url
      end
      pr_average_duration['total_duration'] = pr_average_duration['total_duration'] + duration
      pr_average_duration['count'] = pr_average_duration['count'] + 1
      file_count = get_pr_files(auth, pr_html_url, pr['pull_request']['url'])
      if file_count > pr_with_the_most_files['num_files']
        pr_with_the_most_files['num_files'] = file_count
        pr_with_the_most_files['team_member'] = team_member
        pr_with_the_most_files['url'] = pr_html_url
      end
      if pr_body_length > pr_with_the_longest_body['body_length']
        pr_with_the_longest_body['body_length'] = pr_body_length
        pr_with_the_longest_body['team_member'] = team_member
        pr_with_the_longest_body['url'] = pr_html_url
      end

#      puts "#{team_member}\t#{pr_created_at}\t#{pr_closed_at}\t#{duration.to_s.ljust(10, " ")}\t#{pr_comments.to_s.ljust(11, " ")}\t#{file_count.to_s.ljust(10, " ")}\t#{pr_body_length.to_s.ljust(14, " ")}\t#{pr_html_url}"      
          

    end
    break if result.headers['link'].nil?
    uri = nil
    result.headers['link'].split(", ").each do |link_ref_line|
      link_ref_line.scan(/<(http.*page=(\d+)).*rel.*(last|next)/).each do |link_ref|
        if link_ref[2] == "next"
          uri = link_ref[0]
        end
      end
    end
    break if uri.nil?
  end
  
  pr_changes[team_member] = {
    "test_additions" => @test_additions,
    "test_deletions" => @test_deletions,
    "dev_additions"  => @dev_additions,
    "dev_deletions"  => @dev_deletions,
    "avg_descr_len"  => @avg_total.to_f / @avg_count.to_f 
  }
end

puts "               Total PRs Commented On   Total PRs Merged   Avg Comments on PRs   Dev/Test Ratio   Avg Descr Length"
puts "               ----------------------   ----------------   -------------------   --------------   ----------------"

team_members.each do |team_member|
  total_test = pr_changes[team_member]['test_additions'].to_f - pr_changes[team_member]['test_deletions'];
  total_dev = pr_changes[team_member]['dev_additions'].to_f - pr_changes[team_member]['dev_deletions'];
  puts "#{team_member.ljust(14," ")} #{num_prs_commented[team_member].to_s.ljust(22," ")}   #{num_prs_closed[team_member].to_s.ljust(16," ")}   #{(num_pr_comments[team_member].to_f / num_prs_closed[team_member].to_f).round(2).to_s.ljust(19," ")}   #{(total_test / total_dev).round(2).to_s.ljust(14," ")}   #{pr_changes[team_member]['avg_descr_len'].round(2).to_s.ljust(13," ")}"
end

puts "----"

puts "Average PR time (team)  :"
puts "  Total Duration        : #{get_duration_str(pr_average_duration['total_duration'])}"
puts "  Number PRs            : #{pr_average_duration['count']}"
puts "  Average Duration      : #{get_duration_str(pr_average_duration['total_duration'].to_f / pr_average_duration['count'].to_f)}"

puts "----"

puts "PR with the most comments:"
puts "  Comment Count         : #{pr_with_most_comments['count']}"
puts "  Team Member           : #{pr_with_most_comments['team_member']}"
puts "  PR                    : #{pr_with_most_comments['url']}"

puts "----"

puts "PR open the longest:"
puts "  Duration              : #{get_duration_str(pr_opened_the_longest['duration'])}"
puts "  Team Member           : #{pr_opened_the_longest['team_member']}"
puts "  PR                    : #{pr_opened_the_longest['url']}"

puts "----"

puts "PR open the shortest:"
puts "  Duration              : #{get_duration_str(pr_opened_the_shortest['duration'])}"
puts "  Team Member           : #{pr_opened_the_shortest['team_member']}"
puts "  PR                    : #{pr_opened_the_shortest['url']}"

puts "----"

puts "PR with the most files:"
puts "  Num Files             : #{pr_with_the_most_files['num_files']}"
puts "  Team Member           : #{pr_with_the_most_files['team_member']}"
puts "  PR                    : #{pr_with_the_most_files['url']}"

puts "----"

puts "PR with the largest description:"
puts "  Desc Length           : #{pr_with_the_longest_body['body_length']}"
puts "  Team Member           : #{pr_with_the_longest_body['team_member']}"
puts "  PR                    : #{pr_with_the_longest_body['url']}"
