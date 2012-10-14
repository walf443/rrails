# rrails

Preload rails environment in Remote server to make rails/rake commands faster.

## Requirements

* non-Windows OS
* Ruby 1.9.3

## Usage

Start server:

    $ cd ~/rails_project
    $ export RAILS_ENV=development # optionally
    $ bundle exec rrails-server
    
Run rails/rake commands using rrails:

    $ export RAILS_ENV=development # optionally
    $ rrails -- rails generate model Yakiniku
    $ rrails -- rake db:migrate
    $ rrails -- rake routes
    $ rrails -- rails server
    $ rrails -- rails console
    $ rrails -- pry                # start pry as rails console

    # If you need an interactive console for non rails *console
    # commands, you may want to add '--pty' option.
    # This makes sure that interactive things (like line editing)
    # work correctly, but it also redirect all STDERR to STDOUT
    # and keys like ^C may not work correctly.
    $ rrails --pty -- rails server # use debugger

You may want to add following code to your shell rc file:

    rrails-exec() {
        if pgrep -f rrails-server >/dev/null && grep -q rrails Gemfile.lock &>/dev/null; then
            rrails -- "$@"
        else
            command "$@"
        fi
    }
    alias rails='rrails-exec rails'
    alias rake='rrails-exec rake'

## Description

rails command is too slow. and rake command is too slow under rails environment.
So, rrails can run rails/rake commands by preloaded daemon.

rails-sh is very good solution for this issue. But

* it can't run "rake -T"
* it can't use zsh's histroy.

So I wrote rrails.

## See Also

* guard-rrails: https://github.com/walf443/guard-rrails
* rails-sh: https://github.com/jugyo/rails-sh

## Contributing to rrails
 
* Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet.
* Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it.
* Fork the project.
* Start a feature/bugfix branch.
* Commit and push until you are happy with your contribution.
* Make sure to add tests for it. This is important so I don't break it in a future version unintentionally.
* Please try not to mess with the Rakefile, version, or history. If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.

## Copyright

Copyright (c) 2012 Keiji, Yoshimi. <br>
Copyright (c) 2012 Wu Jun.

See LICENSE.txt for further details.

