.. _idl_optimize:

OVSDB IDL Updating Optimize
===========================

When OVSDB idl setup, it will send a monitor message to OVSDB server to fetch
all rows in register tables. That makes it possible to optimize idl. Just like
what comments in `Row._write
<https://github.com/openvswitch/ovs/blob/master/python/ovs/db/idl.py#L1469-L1498>`_
says::

    If this is a write-only column and the datum being written is the
    same as the one already there, just skip the update entirely.  This
    is worth optimizing because we have a lot of columns that get
    periodically refreshed into the database but don't actually change
    that often.

    We don't do this for read/write columns because that would break
    atomicity of transactions--some other client might have written a
    different value in that column since we read it.  (But if a whole
    transaction only does writes of existing values, without making any
    real changes, we will drop the whole transaction later in
    ovsdb_idl_txn_commit().)

But it also mentions type of columns: write-only and read/write. About the
read/write type, it is quite interesting for my poor knowledge on Neutron ML2
driver, I think most resource get operated within a single worker/thread, it
makes no chances that another thread may read/care about column(s) of a row
in OVN. A exception is neutron-ovn-db-sync-util, the cmdline tool to
synchronize data from Neutron DB to OVN. When synchronizing, you cannot prevent
there is no concurrent operations to update resource in Neutron DB.
