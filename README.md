# rrails

Preload rails environment to make rails/rake commands faster.

## Why?

Without rrails:

    $ time ( rails generate >/dev/null )
    ( rails generate > /dev/null; )  9.29s user 0.41s system 98% cpu 9.807 total
    $ time ( rake routes >/dev/null )
    ( rake routes > /dev/null; )  8.17s user 0.36s system 98% cpu 8.639 total

With rrails:

    $ source <(rrails shellrc)
    $ rrails start                  # optionally

    $ time ( rails generate >/dev/null )
    ( rails generate > /dev/null; )  0.05s user 0.01s system 6% cpu 0.904 total
    $ time ( rake routes >/dev/null )
    ( rake routes > /dev/null; )  0.04s user 0.01s system 12% cpu 0.359 total

## Requirements

* non-Windows OS
* Ruby 1.9.3p194 or above

## Usage

Run rails/rake commands using rrails:

    $ export RAILS_ENV=development         # optionally
    $ rrails rails generate model Yakiniku # first command, slow
    $ rrails rails server                  # fast
    $ rrails rails console                 # fast
    $ rrails rake db:migrate               # fast
    $ rrails rake routes                   # fast
    $ rrails -- rake -T                    # '--' is needed. Otherwise '-T' will be parsed by rrails

For more options, run:

    $ rrails --help

## Shell integration

You may want to add following lines to your shell rc file:

    rrails-exec() {
        if [ -e config/environment.rb ]; then
            # this might be slow, see below
            rrails -- "$@"
        else
            command "$@"
        fi
    }
    alias rails='rrails-exec rails'
    alias rake='rrails-exec rake'

Directly running `rrails` (even without `bundle exec`) may be slow due to levels of dummy wrappers of Bundler.
You can replace `rrails` with an absolute path `/(path_to_rrails_gem)/bin/rrails` to get rid of Bundle initializing code.
This can save about 0.9 seconds.

These lines (with correct absolute path) can be generated by `rrails shellrc`. So you can quickly update your shell rc file using:

    rrails shellrc >> ~/.zshrc

### Bundler

rrails works with bundler. Ususally `bundle exec` (which is slow) is not needed. `gem 'rrails'` is not required in Gemfile, either.

In case you want to make sure Gemfile is in use, or rrails version is specified in Gemfile, just run this before others:

    $ bundle exec rrails start

### PTY mode

rrails's PTY mode makes sure that interactive things (like line editing)
work correctly. Note it also redirect all STDERR to STDOUT and keys like `^C` 
may not work correctly.

PTY mode is enabled only for `rails console` and `rails db` by default.
If you need an interactive console for other commands, you can add `--pty` option:

    $ rrails --pty rails server            # if debugger is in use

### The server

By default, rrails will start a server process on demand per project per rails\_env.
The server writes pid and socket files to `./tmp/` and remove them when exiting.

You can control the server using:

    $ export RAILS_ENV=development         # optionally
    $ rrails stop
    $ rrails restart
    $ rrails reload
    $ rrails status

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

