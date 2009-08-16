require 'wordpress'
require 'modx'
require 'UniversalDetector'
require 'iconv'

class Migration

  def initialize
    @wp   = Wordpress.new
    @modx = ModX.new('Blog')

    @template = @modx.post_template_id
    @root     = @modx.find_content(:pagetitle => 'Blog')

    @default_author = 1
  end

  def find_or_create_blog_year(date)
    parent = @modx.find_content(:pagetitle => date.year.to_s)
    if (parent.nil?)
      STDERR.puts "[migrate] new year #{date.year}"
      modx_blog_year = {
        :type        => 'document',
        :contentType => 'text/html',
        :pagetitle   => date.year.to_s,
        :alias       => date.year.to_s,
        :published   => 1,
        :pub_date    => epochtime,
        :parent      => root,
        :isfolder    => 1,
        :richtext    => 1,
        :template    => @template,
        :searchable  => 1,
        :createdby   => @default_author,
        :createdon   => epochtime,
        :editedby    => @default_author,
        :editedon    => epochtime,
        :publishedby => @default_author,
        :publishedon => epochtime,
      }
      parent = @modx.add_post(modx_blog_year)
    end

    return parent
  end

  def make_utf8(ref, text)
    cd = UniversalDetector::chardet(text)
    if cd['encoding'] != 'utf-8'
      STDERR.puts "[migrate] charset: #{ref} content encoding is #{cd['encoding']} (#{cd['confidence']})"
      begin
        text = Iconv.conv(cd['encoding'], 'utf8', text)
      rescue Iconv::IllegalSequence
        STDERR.puts "[migrate] charset: unable to convert #{ref} from #{cd['encoding']}, leaving intact"
      end
    end
    return text
  end

  def migrate_all_posts
    @wp.posts[0 .. 20 ].each { |wp_post| self.migrate_post(wp_post) }
  end

  def migrate_post(wp_post)
    # date to epochtime
    date      = DateTime.parse(wp_post.post_date)
    epochtime = date.strftime('%s')
    parent    = self.find_or_create_blog_year(date)

    # coerce to utf8
    content = self.make_utf8(wp_post.post_title[0 .. 20 ], wp_post.post_content)

    # WP appears to do this on the fly
    content = "<p>#{content.gsub(/\r\n\r\n/, "</p>\r\n<p>")}</p>"

    modx_post = {
      :type        => 'document',
      :contentType => 'text/html',
      :pagetitle   => wp_post.post_title,
      :longtitle   => wp_post.post_title,
      :alias       => wp_post.post_name,
      :published   => 1,
      :pub_date    => epochtime,
      :parent      => parent,
      :isfolder    => 0,
      :content     => content,
      :richtext    => 1,
      :template    => @template,
      :menuindex   => 0,
      :searchable  => 1,
      :cacheable   => 1,
      :createdby   => @default_author,
      :createdon   => epochtime,
      :editedby    => @default_author,
      :editedon    => epochtime,
      :publishedby => @default_author,
      :publishedon => epochtime,
      :hidemenu    => 0
    }

    @modx.delete_post(modx_post)
    @modx.add_post(modx_post)
    @modx.add_post_categories(modx_post, wp_post.categories.map { |c| c.name })

    modx_comments = []
    wp_post.comments.each do |wp_comment|
      date      = DateTime.parse(wp_comment.comment_date)
      epochtime = date.strftime('%s')
      modx_comment = {
        :title       => '(comment title)',
        :published   => 1,
        :content     => wp_comment.comment_content,
        :createdby   => 0, # 0 here means ModX will look at jot_fields for author, fwict
        :createdon   => epochtime,
        :tagid       => '',
        :flags       => wp_comment.comment_type, # trackback or pingback, unsure if it belongs here
        :mode        => 0,
        :secip       => wp_comment.comment_author_IP,
        :sechash     => 'foo',       # anyone editing the comment (?)

        :name        => wp_comment.comment_author,
        :email       => wp_comment.comment_author_email,
        :url         => wp_comment.comment_author_url
      }
      modx_comments.push modx_comment
    end

    @modx.add_post_comments(modx_post, modx_comments) 
  end

end
