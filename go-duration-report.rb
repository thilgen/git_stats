org_name = "zendesk"

team_members = [
  'team member 1',
  'team member 2',
  'team member 3'
]

date_range = "2019-01-01..2019-01-31"

# generate an access token for your account that has the appropriate access
# https://help.github.com/articles/creating-an-access-token-for-command-line-use/

@auth = {
  :username => "<ADD USERNAME HEERE>",
  :password => "<ADD ACCESS TOKEN HERE>"
}

###################################

require 'httparty'
require 'time_difference'

###################################

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

def get_pr_info(pr)
  pr_html_url = pr['html_url']
  pr_api_url  = pr['pull_request']['url']
  num_files   = 0
  additions   = 0;
  deletions   = 0;
  uri = pr_api_url + "/files"
  loop do
    result = HTTParty.get(uri, :basic_auth => @auth) 
    num_files += result.size 
    result.each do |f|
      additions += f['additions']
      deletions += f['deletions']
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
  return [num_files, additions, deletions, additions + deletions]
end

###################################

# get a list of all the prs created by team_members

repo_stats        = Hash.new(0)
team_member_stats = Hash.new(0)
team_member_stats['all_team'] = Hash.new(0)

puts "team_member\tpr_repo_name\tpr_html_url\tpr_duration_seconds\tpr_duration_friendly\tpr_num_files\tpr_additions\tpr_deletions\tpr_total_changes"

team_members.each do |team_member|
  team_member_stats[team_member] = Hash.new(0)
  uri = "https://api.github.com/search/issues?q=org:#{org_name}+type:pr+author:#{team_member}+created:#{date_range}+is:merged"
  loop do
    result = HTTParty.get(uri, :basic_auth => @auth)
    result['items'].each do |pr|
      pr_comments   = pr['comments']
      pr_repo_name  = pr['repository_url'].match(/^.*\/(.*)$/)[1]
      pr_html_url   = pr['html_url']
      ###
      pr_created_at = pr['created_at']
      pr_closed_at  = pr['closed_at']
      pr_duration   = TimeDifference.between(DateTime.parse(pr_closed_at), DateTime.parse(pr_created_at)).in_seconds
      ###
      unless repo_stats.keys.include?(pr_repo_name) 
        repo_stats[pr_repo_name] = Hash.new(0)
      end
      team_member_stats[team_member]['total_prs'] += 1
      team_member_stats['all_team']['total_prs']  += 1
      repo_stats[pr_repo_name]['total_prs']       += 1
      ###
      team_member_stats[team_member]['total_pr_duration'] += pr_duration
      team_member_stats['all_team']['total_pr_duration'] += pr_duration
      repo_stats[pr_repo_name]['total_pr_duration']      += pr_duration
      ###
      if 0 == team_member_stats[team_member]['shortest_pr_duration'] || team_member_stats[team_member]['shortest_pr_duration'] > pr_duration
        team_member_stats[team_member]['shortest_pr_duration'] = pr_duration
      end
      if 0 == team_member_stats['all_team']['shortest_pr_duration'] || team_member_stats['all_team']['shortest_pr_duration'] > pr_duration
        team_member_stats['all_team']['shortest_pr_duration'] = pr_duration
      end
      if 0 == repo_stats[pr_repo_name]['shortest_pr_duration'] || repo_stats[pr_repo_name]['shortest_pr_duration'] > pr_duration
        repo_stats[pr_repo_name]['shortest_pr_duration'] = pr_duration
      end
      ###
      if team_member_stats[team_member]['longest_pr_duration'] < pr_duration
        team_member_stats[team_member]['longest_pr_duration'] = pr_duration
      end
      if team_member_stats['all_team']['longest_pr_duration'] < pr_duration
        team_member_stats['all_team']['longest_pr_duration'] = pr_duration
      end
      if repo_stats[pr_repo_name]['longest_pr_duration'] < pr_duration
        repo_stats[pr_repo_name]['longest_pr_duration'] = pr_duration
      end
      ###
      pr_info       = get_pr_info(pr)
      pr_files      = pr_info[0]
      pr_adds       = pr_info[1]
      pr_deletions  = pr_info[2]
      pr_changes    = pr_info[3]
      ###
      puts "#{team_member}\t#{pr_repo_name}\t#{pr_html_url}\t#{pr_duration}\t#{get_duration_str(pr_duration)}\t#{pr_info.join("\t")}"
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
end

[team_member_stats, repo_stats].each do |stat_collection|
  stat_collection.each do |stat_member, stats|
    puts stat_member
    total_prs         = stats['total_prs']
    total_pr_duration = stats['total_pr_duration']
    puts "\tTotal PR Count      : #{total_prs}"
    puts "\tTotal PR Duration   : #{get_duration_str(total_pr_duration)}"
    puts "\tShortest PR Duration: #{get_duration_str(stats['shortest_pr_duration'])}"
    puts "\tLongest PR Duration : #{get_duration_str(stats['longest_pr_duration'])}"
    puts "\tAverage PR Duration : #{get_duration_str(total_pr_duration / total_prs)}"
  end
end

# thoughts on using complexity stats - number of files, number of changes, etc.

