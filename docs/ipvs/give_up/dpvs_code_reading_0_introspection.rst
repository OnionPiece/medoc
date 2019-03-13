***************************************
DPVS code reading(part 0) introspection
***************************************

1. slave_lcore_nb & slave_lcore_mask. ctrl module has the two variable,
   while netif module has g_slave_lcore_num and g_slave_lcore_mask
   variables, and they all calculated via netif_get_slave_lcores, so
   they should be used to keep the same values. Why not use a global
   uniq one.

2. slave_lcore_nb vs NETIF_MAX_LCORES. Of caurse, NETIF_MAX_LCORES including
   master lcore, that's not a problem, but variables such as mt_array, mt_lock,
   msg_ring is, since they are initialized via a for-loop with NETIF_MAX_LCORES
   as top. Since slave_lcore_mask has been calculated, why not use it.

3. per-lcore msg queue created via rte_ring_create::

    /* per-lcore msg queue */
    for (ii =0; ii < NETIF_MAX_LCORES; ii++) {
        snprintf(ring_name, sizeof(ring_name), "msg_ring_%d", ii);
        msg_ring[ii] = rte_ring_create(ring_name, msg_ring_size,
                rte_socket_id(), 0/*RING_F_SC_DEQ*/);
        ...

   **rte_socket_id returns the ID of the physical socket of the logical core
   we are running on.**.

   It's quite interesting(suspicious indeed), if we're running on lcore-0,
   which is on physical socket-0, then this for-loop will create
   rings(msg_ring_0 ... msg_ring_63) in physical socket-0 memory. But indeed,
   lcore-16 may running on socket-1.

   Is there any mechanism to ensure it will create ring on which socket they
   are running for each lcores?

4. rte_ring_set_water_mark, API like this may won't work on release than
   DPDK 16.07.

5. Confused inline annotation such as::

    msg_ring[ii] = rte_ring_create(ring_name, msg_ring_size,
            rte_socket_id(), 0/*RING_F_SC_DEQ*/);

   0 should mean multiple-producer and multiple-consumer, since::

      #define RING_F_SP_ENQ 0x0001 /**< The default enqueue is "single-producer". */
      #define RING_F_SC_DEQ 0x0002 /**< The default dequeue is "single-consumer". */ 

6. register netif-lcore-loop-job for Slaves::

    /* register netif-lcore-loop-job for Slaves */
    snprintf(ctrl_lcore_job.name, sizeof(ctrl_lcore_job.name) - 1, "%s", "slave_ctrl_plane");

   why "sizeof(..) - 1", since snprintf will use n-1 by default.
