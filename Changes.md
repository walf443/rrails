v1.0.0				2012-10-16 01:03:00 +0900
 - XXX: It may have many imcopatible changes. "1.0.0" does not mean "stable version".
 - MOD: support UNIXDomainSocket instead of TCPSocket. And UnixDomainSocket is default behaviour. So you can be easy to run rrails in many rails project. But you should run rrails clinet under your project's directory.(thanks quark-zju)
 - MOD: "rails-server" command is obsolate. please use "rrails start" instead. see more about README.md. (thanks quark-zju)
 - MOD: pry command is removed. please use pry hacks instead. https://gist.github.com/941174 (thanks quark-zju)

v0.4.0				2012-10-15 09:56:00 +0900
------------------------------------------------------------------------
 - MOD: pty support. So you can use rails console/server from rrails. (thanks quark-zju)
 - MOD: pry support. (thansk quark-zju)
 - MOD: add --host option. (thanks quark-zju)
 - MOD: Change UNIXDomainSocket to IO.pipe. (thanks quark-zju)

v0.3.1				2012-10-13 18:22:08 +0900
------------------------------------------------------------------------
 - (tag: v0.3.1) Regenerate gemspec for version 0.3.1
 - Version bump to 0.3.1
 - update changes.
 - it should not define constants outside RemoteRails::Server namespace.
 - restyle again.
 - use markdown style.
 - update doc.

v0.3.0				2012-10-13 14:58:02 +0900
------------------------------------------------------------------------
 - FIX: some command that run under 0.1 sec is not output anything .
 - FIX: kill child process(es) when client disconnects (thanks quark-zju)
 - MOD: change reading handling from IO.select to read_nonblocking (thanks quark-zju)
 - FIX: rescure EOFError when reading clisocks (thanks quark-zju)
 - FIX: port number changable.

v0.2.0				2012-09-28 12:55:35 +0900
------------------------------------------------------------------------
 - added reloader.
 - remove_connection is not necessary. included in establish_connection.
 - wrote more doc.

v0.1.0				2012-05-01 10:02:39 +0900
------------------------------------------------------------------------
 - initial release.
