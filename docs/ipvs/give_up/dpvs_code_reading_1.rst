*************************
DPVS code reading(part 1)
*************************

In main, control plane thread, the next to sockopt_ctl is msg_master_process.

msg_master_process
------------------

Both unicast msg and multicast msg can be recieved on Master lcore.

Using a while loop to get dpvs_msg from rte_ring(in msg_ring) for master lcore:
  - update dpvs_msg flags to indicate it has been dequeued
  - get dpvs_msg_type for dpvs_msg
  - if dpvs_msg_type is NULL, call __msg_destroy
  - if dpvs_msg_type mode is UNICAST, try to call unicast_msg_cb for dpvs_msg_type, and call _msg_destroy later
  - if dpvs_msg_type mode is MULTICAST

    - get dpvs_multicast_queue for dpvs_msg per dpvs_msg type and seq
    - if dpvs_multicast_queue is NULL, destroy dpvs_msg_type
    - if dpvs_msg_type doesn't have a valid multicast_msg_cb, destroy dpvs_msg_type
    - if dpvs_msg matches dpvs_multicast_queue mask

      - add dpvs_msg to dpvs_multicast_queue mq(received msg queue) tail
      - update dpvs_msg flags to indicate it has been enqueued(into dpvs_multicast_queue mq) and wait for other slavers reply
      - update dpvs_multicast_queue mask with set dpvs_msg lcore id bit to 0, which should mean reply for multicast from that lcore is done, no more reply msg for such type and seq is expected
      - if dpvs_msg flags contains DPVS_MSG_F_CALLBACK_FAIL, which indicates its relevant callbacks failed on slave lcore, update dpvs_multicast_queue org_msg flags with DPVS_MSG_F_CALLBACK_FAIL
      - if dpvs_multicast_queue mask is 0, which means all slave reply messages arrived

        - try call multicast_msg_cb for dpvs_msg_type
        - destroy dpvs_multicast_queue org_msg

    - destroy dpvs_msg since all reply messages arrived on slaves, this should be a repeated one


about rte_ring_dequeue
----------------------

In msg_master_process, dpvs_msg is dequeued from msg_ring via rte_ring_dequeue, so some questions:
  - where is rte_ring_dequeue also called ?
  - where is rte_ring_enqueue called ?

rte_ring_dequeue will be called in:
  - ctrl module

    - msg_master_process
    - msg_slave_process

  - netif
