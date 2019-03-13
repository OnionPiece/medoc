*********************************
DPVS code reading processing flow
*********************************

ctrl_init
  - rte_rwlock_init(&mc_wait_lock);  // init rte read-write-lock
  - msg_init();                      // init message module

    - init slave_lcore_nb and slave_lcore_mask in ctrl module
    - init mt_array and mt_lock per lcore msg type
    - init mc_wait_list
    - *try to init msg_ring via creating rte_ring for each lcore on socket memory ?*
    - *init ctrl_lcore_job, and register netif-lcore-loop job for slaves ? and where ctrl_lcore_job.func is msg_slave_process*
    - register built-in msg type

  - sockopt_init();                  // init sockopt module

    - init sockopt_list
    - create a stream oriented socket, set it as non-block, bind and listen on unix socket file


main control plane thread
  - try_reload  // reload config
  - sockopt_ctl

    - accept new incomming client, receive dpvs_sock_msg via sockopt_msg_recv
    - get dpvs_sockopts per received dpvs_sock_msg, handle it and reply to client


msg_slave_process
  - dequeue dpvs_msg from rte_ring in msg_ring per lcore id

    - if its multicast msg, call __msg_destroy to destory, then continue
    - if msg type is NULL, call __msg_destroy, then continue
    - if msg type has a valid unicast_msg_cb, run it
    - if msg type mode is DPVS_MSG_MULTICAST, try to make a response dpvs_msg and send it to master lcore, since this multicast message is dispatched from master lcore
    - call __msg_destroy for msg, and update msg type refcnt via msg_type_put
