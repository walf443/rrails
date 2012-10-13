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
