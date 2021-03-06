# Launcher is the core Qwandry class, it coordinates finding and launching
# a package.  It is driven externaly by a UI, for instance the `bin/qw`.
module Qwandry 
  class Launcher
    # The default editor to be used by Qwandry#launch.
    attr_accessor :editor 
    
    # The set of active repositories
    attr_reader :active
  
    # Returns the repositories the Launcher will use.
    attr_reader :repositories
  
    def initialize
      @repositories = Hash.new{|h,k| h[k] = []}
      @active = Set.new
      configure_repositories!
      custom_configuration!
    end
    
    # Adds a repository path to Qwandry's Launcher. `label` is used to label packages residing in the folder `path`.
    # 
    # The `options` can be used to customize the repository.
    # 
    # [:class]        Repository class, defaults to Qwandry::FlatRepository
    # [:accept]       Filters paths, only keeping ones matching the accept option
    # [:reject]       Filters paths, rejecting any paths matching the reject option
    # 
    # `:accept` and `:reject` take patterns such as '*.py[oc]', procs, and regular expressions.
    def add(label, path, options={})
      if path.is_a?(Array)
        path.each{|p| add label, p, options} 
      else
        repository_class = options[:class] || Qwandry::FlatRepository
        label = label.to_s
        @repositories[label] << repository_class.new(label, File.expand_path(path), options)
      end
    end
        
    def activate(*labels)
      labels.each{|label| @active.add label.to_s}
    end
    
    def deactivate(*labels)
      labels.each{|label| @active.delete label.to_s}
    end
      
    # Searches all of the loaded repositories for `name`
    def find(*pattern)
      pattern = pattern.join('*')
      pattern << '*' unless pattern =~ /\*$/
      
      packages = []
      @repositories.select{|label,_| @active.include? label }.each do |label, repos|
        repos.each do |repo|
          packages.concat(repo.scan(pattern))
        end
      end
      packages
    end
  
    # Launches a Package or path represented by a String. Unless `editor` will
    # check against the environment by default.
    def launch(package, editor=nil)
      editor ||= @editor || ENV['VISUAL'] || ENV['EDITOR']
      
      if (!editor) || (editor =~ /^\s*$/) # if the editor is not set, or is blank, exit with a message:
        puts "Please either set EDITOR or pass in an editor to use"
        exit 1
      end
      
      paths = package.is_a?(String) ? [package] : package.paths
      # Editors may have options, 'mate -w' for instance
      editor_and_options = editor.strip.split(/\s+/)
      
      # Launch the editor with its options and any paths that we have been passed
      system(*(editor_and_options + paths))
    end
    
    private
    def configure_repositories!
      # Get all the paths on ruby's load path:
      paths = $:
    
      # Reject binary paths, we only want ruby sources:
      paths = paths.reject{|path| path =~ /#{RUBY_PLATFORM}$/}
    
      # Add ruby standard libraries:
      paths.grep(/lib\/ruby/).each do |path|
        add :ruby, path, :class=>Qwandry::LibraryRepository
      end
    
      # Add gem repositories:
      ($:).grep(/gems/).map{|p| p[/.+\/gems\//]}.uniq.each do |path|
        add :gem, path
      end
      
      # Add perl repositories:
      perl_paths = `perl -e 'foreach $k (@INC){print $k,"\n";}'` rescue ''
      perl_paths.split("\n").reject{|path| path == '' || path == '.'}.each do |path|
        add :perl, path, :class=>Qwandry::LibraryRepository
      end
      
      # add python repositories:
      python_paths = `python -c 'import sys;print \"\\n\".join(sys.path)'` rescue ''
      python_paths.split("\n").reject{|path| path == '' || path == '.' || path =~ /\.zip$/ || path =~/lib-dynload$/}.each do |path|
        add :python, path, :class=>Qwandry::LibraryRepository, :reject => /\.(py[oc])|(egg-info)$/
      end
      
      # Qwandry is a ruby app after all, so activate ruby and rubygems by default.  Other defaults can be set
      # with a custom init.rb
      activate :ruby, :gem
    end
    
    def custom_configuration!
      if config_dir = Qwandry.config_dir
        custom_path = File.join(config_dir, 'init.rb')
        if File.exist?(custom_path)
          begin
            eval IO.read(custom_path), nil, custom_path, 1
          rescue Exception=>ex
            STDERR.puts "Warning: error in custom file: #{custom_path.inspect}"
            STDERR.puts "Exception: #{ex.message}"
            STDERR.puts ex.backtrace
          end
        end
      end
    end
    
  end
end