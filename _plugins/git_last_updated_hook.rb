require 'json'
require 'net/http'
require 'uri'

module Jekyll
    # Git last updated dates
    class GitLastUpdatedGenerator < Generator
        priority :low

        def generate(site)
            site.posts.docs.each do |doc|
                last_modified = git_last_updated(doc.path)
                if last_modified
                    doc.data['last_modified_at'] = last_modified
                else
                    Jekyll.logger.warn "GitLastUpdated:", "No git history found for #{doc.path}"
                end
            end
        end

        private

        def git_last_updated(path)
            git_log = `git log --follow --format=%ad --date=iso-strict -- "#{path}" 2>&1`
            if $?.success? && !git_log.empty?
                git_log.lines.first.strip
            else
                nil
            end
        end
    end

    class GitMetadataGenerator < Generator
        priority :low

        def generate(site)
            Jekyll.logger.debug "GitMetadata:", "Generating git metadata for all posts."
            @user_cache = {}
            site.posts.docs.each do |doc|
                Jekyll.logger.debug "GitMetadata:", "Processing file: #{doc.path}"
                contributors = get_all_contributors(doc.path)
                if contributors
                    Jekyll.logger.debug "GitMetadata:", "author for #{doc.path}: #{contributors['author']}"
                    Jekyll.logger.debug "GitMetadata:", "editors for #{doc.path}: #{contributors['editors']}"

                    doc.data['author'] = contributors[:author]
                    doc.data['editors'] = contributors[:editors]

                    doc.data['author_username'] = contributors[:author]['username']
                    Jekyll.logger.debug "GitMetadata:", "Successfully retrieved git metadata for #{doc.path}"
                else
                    Jekyll.logger.warn "GitMetadata:", "No git history found for #{doc.path}"
                end
            end
        end

        private

        def get_github_username_by_email(email)
            Jekyll.logger.debug "GitMetadata:", "Running get github username by email"
            Jekyll.logger.debug "GitMetadata:", "Retrieving GitHub username for #{email}"
            uri = URI("https://api.github.com/search/commits?q=author-email:#{email}")
            request = Net::HTTP::Get.new(uri)
            request['Accept'] = 'application/vnd.github.cloak-preview+json'
 
            response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
                http.request(request)
            end

            if response.is_a?(Net::HTTPSuccess)
                commits = JSON.parse(response.body)
                if commits['items'] && !commits['items'].empty?
                    commits['items'][0]['committer']['login']
                else
                    "No GitHub username found for #{email}"
                end
            else
                "Failed to retrieve data from GitHub API"
            end
        end

        def user_data_by_email(email)
            email = email.gsub("'", "")

            # File.open('user-emailRequest.txt', 'w') do |file|
            #     # Write content to the file
            #     file.puts "https://api.github.com/search/commits?q=author-email:#{email}"
            # end

            uri = URI("https://api.github.com/search/commits?q=author-email:#{email}")
            request = Net::HTTP::Get.new(uri)
            request['Accept'] = 'application/vnd.github.cloak-preview+json'

            response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
                http.request(request)
            end

            ## Open a file in write mode
            #File.open('user-data.json', 'w') do |file|
            #    # Write content to the file
            #    file.puts response.body
            #end

            if response.is_a?(Net::HTTPSuccess)
                commits = JSON.parse(response.body)
                if commits['items'] && !commits['items'].empty?
                    Jekyll.logger.debug "GitMetadata:", "Committer username for #{email}: #{commits['items'][0]['committer']['login']}"
                    {
                        'username' => commits['items'][0]['committer']['login'],
                        'avatar' => commits['items'][0]['committer']['avatar_url'],
                        'url' => commits['items'][0]['committer']['html_url'],
                        'id' => commits['items'][0]['committer']['id']
                    }
                else
                    "No GitHub username found for #{email}"
                end
            else
                "Failed to retrieve data from GitHub API"
            end
        end

        def get_author_info(path)
            author_email = `git log --format='%ae' --reverse -- #{path} 2>&1`.lines.first&.strip
            if author_email
                user_data_by_email(author_email)
            else
                "No git history found for #{path}"
            end
        end

        def get_editor_info(path)
            # Get all commit emails
            commit_emails = `git log --format='%ae' -- #{path} 2>&1`.lines.map(&:strip)

            # Count the number of commits for each email
            email_counts = commit_emails.each_with_object(Hash.new(0)) do |email, counts|
                counts[email] += 1
            end

            # Get unique emails and map to user data
            editors = email_counts.keys.map do |email|
                Jekyll.logger.debug "GitMetadata:", "Editor email for #{path}: #{email}"
                user_data = user_data_by_email(email)
                if user_data.is_a?(Hash)
                    user_data.merge('contributionsInCurrPage' => email_counts[email])
                end
            end.compact

            # Sort editors by the number of contributions in descending order
            editors.sort_by { |editor| -editor['contributionsInCurrPage'] }
        end

        def get_all_contributors(path)
            {
                'author': get_author_info(path),
                'editors': get_editor_info(path),
            }
        end
    end
end