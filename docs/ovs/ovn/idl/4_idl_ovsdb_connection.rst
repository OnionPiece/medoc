.. _rfc7047: https://tools.ietf.org/html/rfc7047

.. _idl_ovsdb_connection:

***********************************
Idl ovsdb_connection for OVN client
***********************************

Entry point from ovn_client idl
===============================

The enter point for ovsdb_connection(
ovsdbapp.backend.ovs_idl.connection.Connection) creation can be find in topic
:ref:`get ovn idls <get_ovn_idls>`.

.. _ovsdb_connection_init:

As a simple summary, its initialization including:

  - create an ovs.idl.Idl object with:

    - create an ovs.idl.jsonrpc.Session object with openning it, for maintain
      session to server, with:

      - create a ovs.reconnect.Reconnect object with Finite State Machine to
        maintain connection state, connectivity for session
      - enable reconnect object, which cause FSM enter Backoff state [1]

  - create an ovsdbapp.backend.ovs_idl.connection.TransactionQueue to accept
    submitted transaction from ovn_client idl. And the queue:

    - its size is 1 since it only work for one singe worker
    - holds a pipe for outputing I/O event which is listened to/by emulate
      select.poll

and ovsdb_connection will be started in ovn_client idl initialization, as
example, :ref:`ovn_client _nb_idl initialization shows this <nb_idl_init>`.
And also in that, probe interval for the above session get set by config value
from default one.


Start ovsdb_connection
======================

When ovsdb_connection get started, it will:

  - check whether ovs idl has ever connected to server. If not, it will call
    idl.run() to make sure connection to server get created
  - create a ovs.poller.Poller object to get select.poll support (as above
    mentioned) for transaction fetching
  - start a thread as daemon to do transaction handling job

.. _connection_start_code_piece:

code pieces::

    def start(self):
        with self.lock:
            if self.thread is not None:
                return False
            if not self.idl.has_ever_connected():
                idlutils.wait_for_change(self.idl, self.timeout)
                try:
                    self.idl.post_connect()
                except AttributeError:
                    # An ovs.db.Idl class has no post_connect
                    pass
        self.poller = poller.Poller()
        self._is_running = True
        self.thread = threading.Thread(target=self.run)
        self.thread.setDaemon(True)
        self.thread.start()

.. _wait_for_change:

and where idlutils.wait_for_change is::

    def wait_for_change(_idl, timeout, seqno=None):
        if seqno is None:
            seqno = _idl.change_seqno
        stop = time.time() + timeout
        while _idl.change_seqno == seqno and not _idl.run():
            ovs_poller = poller.Poller()
            _idl.wait(ovs_poller)
            ovs_poller.timer_wait(timeout * 1000)
            ovs_poller.block()
            if time.time() > stop:
                raise Exception("Timeout")  # TODO(twilson) use TimeoutException?

the ovs_poller is NOT the one mentioned above for transaction handling, it's a
socket kind, for session stream to establish connection to server.

Transaction handling thread
===========================

The transaction handling thread mentioned above will start with
ovsdb_connection run method as its job, while running:

  - ovsdb_connection transaction queue event will be listened by poller, which
    wake thread up to handle transaction when a transaction is put into queue
  - idl.run() will be called to do lots of jobs including connection verifying,
    messaging receiving/sending and relavant process [2], more will be
    discussed later
  - then transaction will be get from queue, it get executed via its do_commit
    method, in which an ovs idl transaction will be created to arrange messages
    from commands, and handle transaction submit messages to server via
    rpc
  - if no exception raises, execution result will be put into transaction
    results queue

code pieces::

    def run(self):
        while self._is_running:
            self.idl.wait(self.poller)
            self.poller.fd_wait(self.txns.alert_fileno, poller.POLLIN)
            # TODO(jlibosva): Remove next line once losing connection to ovsdb
            #                 is solved.
            self.poller.timer_wait(self.timeout * 1000)
            self.poller.block()
            self.idl.run()
            txn = self.txns.get_nowait()
            if txn is not None:
                try:
                    txn.results.put(txn.do_commit())
                except Exception as ex:
                    er = idlutils.ExceptionResult(ex=ex,
                                                  tb=traceback.format_exc())
                    txn.results.put(er)
                self.txns.task_done()

So the transaction handling thread just looks like a pipe. Itself doesn't have
any ability do process commands transaction, but just receive/collect them
from northbound like ovn client, and call ovs idl and transaction to do handle
in message transaction level.

About how does ovs idl transaction do its job will not be discussed at this
moment.

Next I'd like to discuss how connection to server is build, since in
[1], reconnect, the connectivity finite state machine, just enters Backoff
stage, not stage for an established connection. And once transaction handling
thread get started, it needs connection get ready for session/rpc message
transmition. So I think it's necessary to figure out that how connection is
build.

Idl run
=======

In [2], I tried to list some work about idl.run will do, but that's not all.
For my purpose, if connection is not in connected stage, when idl run is
called, it will try to make connection enter established stage.

Before the thread get started in ovsdb_connection start method,
idlutils.wait_for_change which trigger idl run will be called, in case idl has
not connected to server before. :ref:`ovsdb_connection start code piece
<connection_start_code_piece>` shows this. And this should be the first time idl
run get called.

When idl run is called, it will call session run, the session is the one in
the above :ref:`ovsdb_connection initialization part <ovsdb_connection_init>`.
And after that, idl check if session is connected, break its processing if not,

.. _idl_run_code_pieces:

code pieces look like::

    run
        initial_change_seqno = self.change_seqno
        self._session.run()
        while i < 50:
            if not self._session.is_connected():
                break

            seqno = self._session.get_seqno()
            if seqno != self._last_seqno:
                self._last_seqno = seqno
                self.__txn_abort_all()
                self.__send_monitor_request()
                if self.lock_name:
                    self.__send_lock_request()
                break

            ...(further porocessing on messages) ...
        return initial_change_seqno != self.change_seqno

and where session.is_conection is::

    is_connected
        return self.rpc is not None

once it's connected, session will create a rpc object which is used to send
jsonrpc messages to server, so only if rpc exists can tell connection
is build up.

change_seqno is initialized as 0, and you can find its explanation at `github
<https://github.com/openvswitch/ovs/blob/master/python/ovs/db/idl.py#L65-L72>`_
. Personally, I think it's that change_seqno will be increased every time
client side idl get messages from server. So in :ref:`wait_for_change
<wait_for_change>`, it use chagne_seqno as condition to determine whether
idl get connected to server, since once rpc is ready, idl will send a monitor
request to server to fetch content of all rows in registered tables. For
monitor request, you can check it in `RFC-7047 monitor
<https://tools.ietf.org/html/rfc7047#page-16>`_.

The reason idl need inquire current records in DB is for idl optimization, like
to do content comparison for any updating operations from ovn client(check
:ref:`idl optimize <idl_optimize>`), and to return results for quering from ovn
client directly without inquire server again.

Session run
===========

Session get initialized with empty stream and rpc it get opened in
:ref:`ovsdb_connection initialization <ovsdb_connection_init>`, and no stream
and rpc means no connecting action has been taken. So for the first time
session get run, it needs to take action to build connection.

When session run is called, reconnect run will be called to trigger FSM
state changing, and as a result, an action session need to do will be returned.

Since FSM has entered Backoff state in [1], this time, it will enter
ConnectInProgress state, and return CONNECT action to tell session that it's
time to build connection to server, as a result stream will be created for
session.

Stream is bidirectional byte stream, such as unix domain sockets, tcp and ssl.
Per `rfc7047`_, OVSDB use json as message format, so only stream is not enought
for idl client to communicate with server, session.rpc is need for this.

The first time session run only creates a stream, it's not ready for
connection. Per :ref:`idl run code pieces <idl_run_code_pieces>`, idl run will
return False since change_seqno doesn't change, and it causes idl run again in
:ref:`wait_for_change <wait_for_change>`. This time, session notices stream is
ready(not None), so it will try to build rpc on stream, and trigger reconnect
to do FSM state changing. FSM will enter Active state, which means connected,
and new action PROBE will tell session to send
`echo message <https://tools.ietf.org/html/rfc7047#page-22>`_ to maintain
connection to server. Once rpc get created, session is connected.

Code pieces looks like::

    run
        ...
        elif self.stream is not None:
            error = self.stream.connect()
            if error == 0:
                self.reconnect.connected(ovs.timeval.msec())
                self.rpc = Connection(self.stream)
                self.stream = None
            elif error != errno.EAGAIN:
              ...

        action = self.reconnect.run(ovs.timeval.msec())
        if action == ovs.reconnect.CONNECT:
            self.__connect()
        elif action == ovs.reconnect.DISCONNECT:
            self.reconnect.disconnected(ovs.timeval.msec(), 0)
            self.__disconnect()
        elif action == ovs.reconnect.PROBE:
            if self.rpc:
               ...(send echo message)...

and where __connect is::

    __connect
        name = self.reconnect.get_name()
        if not self.reconnect.is_passive():
            error, self.stream = ovs.stream.Stream.open(name)
            if not error:
                self.reconnect.connecting(ovs.timeval.msec())
