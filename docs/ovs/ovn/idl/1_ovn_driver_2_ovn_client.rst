*****************************************
From Neutron ML2/OVN driver to OVN client
*****************************************

In networking-ovn entry_points, we can find ovn driver is
networking_ovn.ml2.mech_driver:OVNMechanismDriver. Neutron will use it to
create idl, which maintains connection to OVN DB server, translates Neutron
data to format OVN can understand, and maintains DB consistant between Neutron
DB and OVN DB.
In this serail of topics, I will use server to indicate OVN DB server.

For non-native drivers, ML2 use precommit and postcommit to notify them. As an
example, I will use create_network_postcommit as a entry point to trace
code/logic.

I will not paste all code, but just some pseudo-code pieces with some comments
to helper understanding. So it means some details will be ignored, and to find
that, source code checking is needed.

First in networking_ovn/ml2/mech_driver.py, in class OVNMechanismDriver::

    create_network_postcommit
        network = context.current
        self._ovn_client.create_network(network)

    @property
    _ovn_client
        if self._ovn_client_inst is None:
            if not(self._nb_ovn and self._sb_ovn):
                # Wait until the post_fork_initialize method has finished and
                # IDLs have been correctly setup.
                self._post_fork_event.wait()
            self._ovn_client_inst = ovn_client.OVNClient(self._nb_ovn, self._sb_ovn)
        return self._ovn_client_inst

The _post_fork_event is an instance of threading.Event and get initialled in
OVNMechanismDriver method. _post_fork_event.wait() will wait until a flag of
_post_fork_event is set to True by _post_fork_event.set(), which is done in::

    post_fork_initialize
        self._post_fork_event.clear()
        self._nb_ovn, self._sb_ovn = impl_idl_ovn.get_ovn_idls(self, trigger)
        self._post_fork_event.set()

    subscribe
        registry.subscribe(self.post_fork_initialize,
                           resources.PROCESS,
                           events.AFTER_INIT)

So after OVNMechanismDriver get created, it will subscribe (neutron-server)
process(es) AFTER_INIT (initializatin totally done) event, to trigger
post_fork_initialize method, in which :ref:`idls to OVN northbound and
southbound DB will be created <get_ovn_idls>`. And OVN client will be created
based on the created idls.

Let check create_network method in OVN client, in
networking_ovn/common/ovn_client.py, class OVNClient::

    create_network
        with self._nb_idl.transaction(check_error=True) as txn:
            txn.add(self._nb_idl.ls_add(lswitch_name, external_ids=ext_ids))

as an example, it shows the common processing how does Neutron ML2/OVN driver
pass operations to OVN, by OVN client:

- open an transaction for idl to handle
- generate a command object like what _nb_idl.ls_add does
- add the command object into transaction
