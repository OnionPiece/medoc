.. _test_this_locally:


*****************
Test this locally
*****************

Note
----

Indeed, this is just a note for myself to remember how I build this things.
Recommand reading this `getting_started
<http://matplotlib.org/sampledoc/getting_started.html>`_


Point your browser to
---------------------

For beginners like me, who has no experience about webserver, need some ways
to test things local and AQAP. And I think apache2 is good for this. I install
it on my environment (Ubuntu 16.04) and test things just by a few steps.

First install apache2, start apache2 or ensure it's running::

  lizk@ubuntu:~/zongkai_docs$ sudo apt install apache2
  Reading package lists... Done
  ... (outputs are ignored)
  lizk@ubuntu:~/zongkai_docs$ service apache2 status
  ... (outputs are ignored)
     Active: active (running) since Mon 2017-09-04 21:27:26 PDT; 47s ago
  ... (outputs are ignored)

Next, get my mechine's IP and access it with web browser, to make sure apache2
works fine.

Later, write a simple hello world page, and build, and copy all things under
_build/html/ to /var/www/html/, since apache2's entrance is there::

  lizk@ubuntu:~/zongkai_docs$ sudo cp -r _build/html/* /var/www/html/

Nothing reload need to be done, since I didn't change any configurations of
apache2.

Using web browser to access again. The new changing can be tested locally.
