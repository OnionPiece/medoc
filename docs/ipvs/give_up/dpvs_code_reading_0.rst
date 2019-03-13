*************************
DPVS code reading(part 0)
*************************

main
----

From function main in main.c, it has::

    /* start control plane thread */
    while (1) {
        /* reload configuations if reload flag is set */
        try_reload();
        /* IPC loop */
        sockopt_ctl(NULL);
        /* msg loop */
        msg_master_process();
        /* timer */
        loop_cnt++;
        if (loop_cnt % timer_sched_loop_interval == 0)
            rte_timer_manage();
        /* kni */
        kni_process_on_master();

        /* increase loop counts */
        netif_update_master_loop_cnt();
    }

As the annotation mentioned, this is main entrance for control plane thread.


try_reload
----------

For function try_reload, it is defined as::

    void try_reload(void)
    {
        if (unlikely(RELOAD_STATUS)) {
            UNSET_RELOAD;
            /* using default configuration file */
            load_conf_file(NULL);
        }
    }

so it's about configuration loading.


sockopt_ctl & ctrl_init
--------------------------

still in main
`````````````

For function sockopt_ctl, before the while loop, there is a *if* block about
function ctrl_init::

    if ((err = ctrl_init()) != 0 )
        rte_exit(EXIT_FAILURE, "Fail to init ctrl plane: %s\n",
                 dpvs_strerror(err));

Both function ctrl_init and function sockopt_ctl are defined in src/ctrl.c.
And that file is what we should dig next.


ctrl_init
`````````

ctrl_init has 3 main sub-init jobs to do, 3 functions to call indeed::

    rte_rwlock_init(&mc_wait_lock);

    ret = msg_init();
    ...
    ret = sockopt_init();


rte_rwlock_init
:::::::::::::::

rte_rwlock_init is a DPDK API::

    /**
     * Initialize the rwlock to an unlocked state.
     *
     * @param rwl
     *   A pointer to the rwlock structure.
     */
    static inline void
    rte_rwlock_init(rte_rwlock_t *rwl)
    {
            rwl->cnt = 0;
    }

and for mc_wait_lock, itself and its type are defined as::

    rte_rwlock_t mc_wait_lock;
    
    /**
     * The rte_rwlock_t type.
     *
     * cnt is -1 when write lock is held, and > 0 when read locks are held.
     */
    typedef struct {
            volatile int32_t cnt; /**< -1 when W lock held, > 0 when R locks held. */
    } rte_rwlock_t;

Interesting, multiple read seem can increase cnt, like a reference count.

And it seems what ret_rwlock_init to do is initializing a global read-write
lock mc_wait_lock, multicast wait lock. The mc_wait_lock will only be used
with rte_rwlock_write_lock and rte_rwlock_write_unlock within
multicast_msg_send, which indicates that it only works for multicast.


msg_init
::::::::

What the msg_init do is to initialize the message module.

msg_init calls::

    master_lcore = rte_get_master_lcore();

a DPDK API to *Get the id of the master lcore*.
Then function netif_get_slave_lcores in src/netif.c to assigned slave_lcore_nb
and slave_lcore_mask::

    netif_get_slave_lcores(&slave_lcore_nb, &slave_lcore_mask);


netif_get_slave_lcores
......................

lcore means logical core.
netif_get_slave_lcores is defined as::

    void netif_get_slave_lcores(uint8_t *nb, uint64_t *mask)
    {
        int i = 0;
        uint64_t slave_lcore_mask = 0L;
        uint8_t slave_lcore_nb = 0;
    
        while (lcore_conf[i].nports > 0) {
            slave_lcore_nb++;
            slave_lcore_mask |= (1L << lcore_conf[i].id);
            i++;
        }
    
        if (nb)
            *nb = slave_lcore_nb;
        if (mask)
            *mask = slave_lcore_mask;
    }

About what does netif_get_slave_lcores do will be described later.
About lcore_conf::

    /* worker configuration array */
    static struct netif_lcore_conf lcore_conf[NETIF_MAX_LCORES + 1];
    
    /* Note: Lockless, lcore_conf is set on initialization stage by cfgfile /etc/dpvs.conf.
    config sample:
    static struct netif_lcore_conf lcore_conf[NETIF_MAX_LCORES + 1] = {
        {.id = 1, .nports = 2, .pqs = {
            {.id = 0, .nrxq = 1, .ntxq = 1, .rxqs = {{.id = 0, }, }, .txqs = {{.id = 0, }, }, },
            {.id = 1, .nrxq = 0, .ntxq = 1, .txqs = {{.id = 0, }, }, }, },
        },
        {.id = 2, .nports = 2, .pqs = {
            {.id = 0, .nrxq = 1, .ntxq = 1, .rxqs = {{.id = 1, }, }, .txqs = {{.id = 1, }, }, },
            {.id = 1, .nrxq = 1, .ntxq = 2, .rxqs = {{.id = 0, }, }, .txqs = {{.id = 1, }, {.id = 4, }}, }, },
        },
        {.id = 3, .nports = 2, .pqs = {
            {.id = 0, .nrxq = 2, .ntxq = 1, .rxqs = {{.id = 2, }, {.id = 3, }, }, .txqs = {{.id = 2, }, }, },
            {.id = 1, .nrxq = 1, .ntxq = 2, .rxqs = {{.id = 1, }, }, .txqs = {{.id = 2, }, {.id = 3, }, }, }, },
        },
    };
    */

    #define NETIF_MAX_LCORES            64

and where netif_lcore_conf::

    /*
     *  lcore conf
     *  Multiple ports may be processed by a lcore.
     */
    struct netif_lcore_conf
    {
        lcoreid_t id;
        /* nic number of this lcore to process */
        int nports;
        /* port list of this lcore to process */
        struct netif_port_conf pqs[NETIF_MAX_PORTS];
    } __rte_cache_aligned;

    typedef uint8_t lcoreid_t;

and netif_port_conf::

    /*
     * RX/TX port conf for lcore.
     * Multiple queues of a port may be processed by a lcore.
     */
    struct netif_port_conf
    {
        portid_t id;
        /* rx/tx queues for this lcore to process*/
        int nrxq;
        int ntxq;
        /* rx/tx queue list for this lcore to process */
        struct netif_queue_conf rxqs[NETIF_MAX_QUEUES];
        struct netif_queue_conf txqs[NETIF_MAX_QUEUES];
    } __rte_cache_aligned;

and netif_queue_conf::

    /* RX/TX queue conf for lcore */
    struct netif_queue_conf
    {
        queueid_t id;
        uint16_t len;
        uint16_t kni_len;
        struct rx_partner *isol_rxq;
        struct rte_mbuf *mbufs[NETIF_MAX_PKT_BURST];
        struct rte_mbuf *kni_mbufs[NETIF_MAX_PKT_BURST];
    } __rte_cache_aligned;

    /* maximum pkt number at a single burst */
    #define NETIF_MAX_PKT_BURST         32

hmm, pkt number, will this ingores pkt size difference?

So, it may looks like::

    logical relation: lcore->port->queue

    netif_lcore_conf records bindings for port to lcore
    netif_port_conf records bindings for queue to port

So what does netif_get_slave_lcores do? It traverse lcore->port binding maps,
to find all lcores used/configured for dpvs, with:

  1. slave_lcore_nb is a counter to get number of lcores
  2. slave_lcore_mask is a long int to build a mask to record lcores

obviously, dpvs won't use all lcores on machine, it also needs some lcores to
server for management and maintainment.


per-lcore msg type array init
.............................

The next to netif_get_slave_lcores is::

    /* per-lcore msg type array init */
    for (ii = 0; ii < NETIF_MAX_LCORES; ii++) {
        for (jj = 0; jj < DPVS_MSG_LEN; jj++) {
            INIT_LIST_HEAD(&mt_array[ii][jj]);
            rte_rwlock_init(&mt_lock[ii][jj]);
        }
    }

What are mt_array and mt_lock, where are they initialized ?
They and their type are::

    msg_type_array_t mt_array[NETIF_MAX_LCORES];
    msg_type_lock_t mt_lock[NETIF_MAX_LCORES];

    /* per-lcore msg-type array */
    typedef struct list_head msg_type_array_t[DPVS_MSG_LEN];
    typedef rte_rwlock_t msg_type_lock_t[DPVS_MSG_LEN];

So for a lcore:

  - mt_array(message type array) will build a bidirectional chain
  - mt_lock will build a rte_rwlock_t array
  - they can be visited via:
    mt_*array[core_index][msg_type_index]

Some questions:

  - What's difference between master and slave lcores?
  - What's the purpose to define and use master and slave lcores?


multicast queue init
....................

Next is::

    /* multicast queue init */
    mc_wait_list.free_cnt = msg_mc_qlen;
    INIT_LIST_HEAD(&mc_wait_list.list);

mc_wait_list and its relavant type is::

    /* multicast_queue list (Master lcore only) */
    struct multicast_wait_list {
        uint32_t free_cnt;
        struct list_head list;
    };
    struct multicast_wait_list mc_wait_list;

So seems, only master lcore will handle multicase ?


per-lcore msg queue
...................

Next is::

    /* per-lcore msg queue */
    for (ii =0; ii < NETIF_MAX_LCORES; ii++) {
        snprintf(ring_name, sizeof(ring_name), "msg_ring_%d", ii);
        msg_ring[ii] = rte_ring_create(ring_name, msg_ring_size,
                rte_socket_id(), 0/*RING_F_SC_DEQ*/);
        if (unlikely(NULL == msg_ring[ii])) {
            RTE_LOG(ERR, MSGMGR, "Fail to init ctrl !\n");
                    return EDPVS_DPDKAPIFAIL;
        }
        rte_ring_set_water_mark(msg_ring[ii], (int)(msg_ring_size * 0.8));
    }

where rte_ring_create is a DPDK API::

    /**
     * Create a new ring named *name* in memory.
     *
     * This function uses ``memzone_reserve()`` to allocate memory. Then it
     * calls rte_ring_init() to initialize an empty ring.
     *
     * The new ring size is set to *count*, which must be a power of
     * two. Water marking is disabled by default. The real usable ring size
     * is *count-1* instead of *count* to differentiate a free ring from an
     * empty ring.
     *
     * The ring is added in RTE_TAILQ_RING list.
     *
     * @param name
     *   The name of the ring.
     * @param count
     *   The size of the ring (must be a power of 2).
     * @param socket_id
     *   The *socket_id* argument is the socket identifier in case of
     *   NUMA. The value can be *SOCKET_ID_ANY* if there is no NUMA
     *   constraint for the reserved zone.
     * @param flags
     *   An OR of the following:
     *    - RING_F_SP_ENQ: If this flag is set, the default behavior when
     *      using ``rte_ring_enqueue()`` or ``rte_ring_enqueue_bulk()``
     *      is "single-producer". Otherwise, it is "multi-producers".
     *    - RING_F_SC_DEQ: If this flag is set, the default behavior when
     *      using ``rte_ring_dequeue()`` or ``rte_ring_dequeue_bulk()``
     *      is "single-consumer". Otherwise, it is "multi-consumers".
     * @return
     *   On success, the pointer to the new allocated ring. NULL on error with
     *    rte_errno set appropriately. Possible errno values include:
     *    - E_RTE_NO_CONFIG - function could not get pointer to rte_config structure
     *    - E_RTE_SECONDARY - function was called from a secondary process instance
     *    - EINVAL - count provided is not a power of 2
     *    - ENOSPC - the maximum number of memzones has already been allocated
     *    - EEXIST - a memzone with the same name already exists
     *    - ENOMEM - no appropriate memory area found in which to create memzone
     */
    struct rte_ring *rte_ring_create(const char *name, unsigned count,
                                     int socket_id, unsigned flags);

and check again::

    msg_ring[ii] = rte_ring_create(ring_name, msg_ring_size,
            rte_socket_id(), 0/*RING_F_SC_DEQ*/);

so for now, things to notice:

  - ring_name stands for a ring, which is generated by::

      snprintf(ring_name, sizeof(ring_name), "msg_ring_%d", ii);

  - msg_ring_size is the usable ring size. And msg_ring_size is::

      #define DPVS_MSG_RING_SIZE_DEF 4096
      static uint32_t msg_ring_size = DPVS_MSG_RING_SIZE_DEF;

  - **rte_socket_id returns the ID of the physical socket of the logical core
    we are running on.**.

    It's quite interesting(suspicious indeed), if we're running on lcore-0,
    which is on physical socket-0, then this for-loop will create
    rings(msg_ring_0 ... msg_ring_63) in physical socket-0 memory. But indeed,
    lcore-16 may running on socket-1.

    Is there any mechanism to ensure it will create ring on which socket they
    are running for each lcores?
    
  - 0/*RING_F_SC_DEQ*/. Since flags are *"An OR of the following"*, and defined
    flags are::

      #define RING_F_SP_ENQ 0x0001 /**< The default enqueue is "single-producer". */
      #define RING_F_SC_DEQ 0x0002 /**< The default dequeue is "single-consumer". */ 

    so, 0 means multiple-producer and multiple-consumer.

    Not sure what does the inline annotation try to mean?

A question, where will be slave_lcore_nb and slave_lcore_mask be used?

And msg_ring is an array of rte_rings::

    /* per-lcore msg queue */
    struct rte_ring *msg_ring[NETIF_MAX_LCORES];

About rte_ring_set_water_mark, I'm not sure what it should be, since I found
in dpdk/doc/guides/rel_notes/release_17_05.rst, it get removed::

  * Removed the function ``rte_ring_set_water_mark`` as part of a general
    removal of watermarks support in the library.


register netif-lcore-loop-job for Slaves
........................................

Next is::

    /* register netif-lcore-loop-job for Slaves */
    snprintf(ctrl_lcore_job.name, sizeof(ctrl_lcore_job.name) - 1, "%s", "slave_ctrl_plane");
    ctrl_lcore_job.func = slave_lcore_loop_func;
    ctrl_lcore_job.data = NULL;
    ctrl_lcore_job.type = NETIF_LCORE_JOB_LOOP;
    if ((ret = netif_lcore_loop_job_register(&ctrl_lcore_job)) < 0) {
        RTE_LOG(ERR, MSGMGR, "[%s] fail to register ctrl func on slave lcores\n", __func__);
        return ret;
    }

About ctrl_lcore_job::

    struct netif_lcore_loop_job ctrl_lcore_job;

    struct netif_lcore_loop_job
    {
        char name[32];
        void (*func)(void *arg);
        void *data;
        enum netif_lcore_job_type type;
        uint32_t skip_loops; /* for NETIF_LCORE_JOB_SLOW type only */
    #ifdef CONFIG_RECORD_BIG_LOOP
        uint32_t job_time[NETIF_MAX_LCORES];
    #endif
        struct list_head list;
    } __rte_cache_aligned;

As we can see:

  - func is a function pointer which point to a function accept void arguments
    and return void;
  - type::

      enum netif_lcore_job_type {
          NETIF_LCORE_JOB_INIT      = 0,
          NETIF_LCORE_JOB_LOOP      = 1,
          NETIF_LCORE_JOB_SLOW      = 2,
          NETIF_LCORE_JOB_TYPE_MAX  = 3,
      };

So slave_lcore_loop_func is a such kind of void function, it will call
msg_slave_process. msg_slave_process's defination has a annotation::

    /* only unicast msg can be recieved on Slave lcore */

So, for info we can get for now, all slave lcores are used to handle unicast
while master lcore is used to handle multicast. OK, this explains their
purpose, but what about the defination about master and slave roles, what
defines a master role and what to slave?

msg_slave_process will:

  - use rte_lcore_id and rte_get_master_lcore to get the ID of the execution
    unit we are running on, and the id of the master lcore. Then check whether
    current execution unit is master lcore.
  - use a while loop::

      /* dequeue msg from ring on the lcore until drain */
      while (0 == rte_ring_dequeue(msg_ring[cid], (void **)&msg)) {

    to dequeue msg from ring on current lcore until drain. And rte_ring_dequeue
    is defined as::

      /**
       * Dequeue one object from a ring.
       *
       * This function calls the multi-consumers or the single-consumer
       * version depending on the default behaviour that was specified at
       * ring creation time (see flags).
       *
       * @param r
       *   A pointer to the ring structure.
       * @param obj_p
       *   A pointer to a void * pointer (object) that will be filled.
       * @return
       *   - 0: Success, objects dequeued.
       *   - -ENOENT: Not enough entries in the ring to dequeue, no object is
       *     dequeued.
       */
      static __rte_always_inline int
      rte_ring_dequeue(struct rte_ring *r, void **obj_p)
      {
              return rte_ring_dequeue_bulk(r, obj_p, 1, NULL) ? 0 : -ENOENT;
      }

    as mentioned before, the ring is created in multi-consumers version. And
    msg is::

      struct dpvs_msg *msg, *xmsg;

    which matches rte_ring_dequeue annotation mentioned.
    And for success, it returns 0, not a message, so *msg* as a pointer, should
    be point to a allocated message when rte_ring_dequeue_bulk processes.

    And dpvs_msg is defined as::

      /* inter-lcore msg structure */
      struct dpvs_msg {
          struct list_head mq_node;
          msgid_t type;
          uint32_t seq;           /* msg sequence number */
          DPVS_MSG_MODE mode;     /* msg mode */
          lcoreid_t cid;          /* which lcore the msg from, for multicast always Master */
          uint32_t flags;         /* msg flags */
          rte_spinlock_t f_lock;  /* msg flags lock */
          struct dpvs_msg_reply reply;
          /* response data, created with rte_malloc... and filled by callback */
          uint32_t len;           /* msg data length */
          char data[0];           /* msg data */
      };

    its mode and flags will be shown later, and dpvs_msg_reply is::

      struct dpvs_msg_reply {
          uint32_t len;
          void *data;
      };

    For more code digging in DPDK, what *msg* points to, is not a new space
    allocated, but a object in ring. When message object get inserted into ring
    is a question to figure out later, but not for now.

  - update message state flags by OR with DPVS_MSG_F_STATE_RECV, while
    DPVS_MSG_F_STATE_RECV means msg has dequeued from ring, within spinlock.
    So msg is shared resource ? All flags are::

      /* nonblockable msg */
      #define DPVS_MSG_F_ASYNC            1
      /* msg has been sent from sender */
      #define DPVS_MSG_F_STATE_SEND       2
      /* for multicast msg only, msg arrived at Master and enqueued, waiting for all other Slaves reply */
      #define DPVS_MSG_F_STATE_QUEUE      4
      /* msg has dequeued from ring */
      #define DPVS_MSG_F_STATE_RECV       8
      /* msg finished, all Slaves replied if multicast msg */
      #define DPVS_MSG_F_STATE_FIN        16
      /* msg drop, callback not called,  for reason such as unregister, timeout ... */
      #define DPVS_MSG_F_STATE_DROP       32
      /* msg callback failed */
      #define DPVS_MSG_F_CALLBACK_FAIL    64
      /* msg timeout */
      #define DPVS_MSG_F_TIMEOUT          128

  - check msg mode, if it is DPVS_MSG_MULTICAST(the other is DPVS_MSG_UNICAST),
    then call __msg_destroy(internal msg destroy function: free asynchronous
    msg internally) to handle::

      __msg_destroy(&msg, DPVS_MSG_F_STATE_DROP);

    __msg_destroy will first check whehter DPVS_MSG_F_ASYNC is set as one of
    msg flags within a spinlock. If not, add give flag(DPVS_MSG_F_STATE_DROP)
    as msg flag, and return.

    If DPVS_MSG_F_ASYNC is already one of msg flags, then check whether msg
    mode is DPVS_MSG_MULTICAST. If true, then calls mc_queue_get to get
    dpvs_multicast_queue where this msg is on::

      struct dpvs_multicast_queue *mcq;

      mcq = mc_queue_get(msg->type, msg->seq);
      
      /* only be called on Master, thus no lock needed */
      static inline struct dpvs_multicast_queue* mc_queue_get(msgid_t type, uint32_t seq)
      {
          struct dpvs_multicast_queue *mcq;
          list_for_each_entry(mcq, &mc_wait_list.list, list)
              if (mcq->type == type && mcq->seq == seq) {
                  return mcq;
              }
          return NULL;
      }

    where dpvs_multicast_queue is::

      /* Master->Slave multicast msg queue */
      struct dpvs_multicast_queue {
          msgid_t type;           /* msg type */
          uint32_t seq;           /* msg sequence number */
          //uint16_t ttl;           /* time to live */
          uint64_t mask;          /* bit-wise core mask */
          struct list_head mq;    /* recieved msg queue */
          struct dpvs_msg *org_msg; /* original msg from 'multicast_msg_send', sender should never visit me */
          struct list_head list;
      };

    where mc_wait_list is mentioned above in "multicast queue init" part. And
    mc_wait_list.list is just a bidirection chain to get dpvs_multicast_queue
    all chained together.

    If mcq exists, then::

      list_for_each_entry_safe(cur, next, &mcq->mq, mq_node) {
          list_del_init(&cur->mq_node);
          //__msg_destroy(&cur, flags);
          if (cur->reply.data)
              rte_free(cur->reply.data);
          rte_free(cur);
      }

    where cur and next are::

      struct dpvs_msg *cur, *next;

    It walks throught mq(bidirection chain), call list_del_init to remove msg
    mq_node from mq, which means remove msg from chained message queue, and
    update msg mq_node to point to mq_node itself. Delete reply data if msg
    has.

    And finally, mcq get deleted, msg get freed with its reply data::

      list_del_init(&mcq->list);
      mc_wait_list.free_cnt++;
      rte_free(mcq);

      if (msg->reply.data) {
          msg->reply.len = 0;
          rte_free(msg->reply.data);
      }
      rte_free(msg);

  - check msg type, if NULL, then call __msg_destroy to delete. Where msg tpye
    is::

      struct dpvs_msg_type *msg_type;

      /* unicast only needs UNICAST_MSG_CB,
       * while multicast need both UNICAST_MSG_CB and MULTICAST_MSG_CB.
       * As for mulitcast msg, UNICAST_MSG_CB return a dpvs_msg to Master with the SAME
       * seq number as the msg recieved. */
      struct dpvs_msg_type {
          msgid_t type;
          lcoreid_t cid;          /* on which lcore the callback func registers */
          DPVS_MSG_MODE mode;     /* distinguish unicast from multicast for the same msg type */
          UNICAST_MSG_CB unicast_msg_cb;     /* call this func if msg is unicast, i.e. 1:1 msg */
          MULTICAST_MSG_CB multicast_msg_cb; /* call this func if msg is multicast, i.e. 1:N msg */
          rte_atomic32_t refcnt;
          struct list_head list;
      };

      /* All msg callbacks are called on the lcore which it registers */
      typedef int (*UNICAST_MSG_CB)(struct dpvs_msg *);
      typedef int (*MULTICAST_MSG_CB)(struct dpvs_multicast_queue *);

      typedef uint32_t msgid_t;

    It use msg_type_get to get msg::

      msg_type = msg_type_get(msg->type, /*msg->mode, */cid);

    which will walk throught all chained dpvs_msg_type with bidirection
    chain mt_array.

  - then if msg_type has a valid unicast_msg_cb, run it. If callback function
    failed, update msg flags with DPVS_MSG_F_CALLBACK_FAIL.

  - next, if msg_type mode is DPVS_MSG_MULTICAST(hmm, doesn't msg mode also
    should be DPVS_MSG_MULTICAST? If so, will this be a duplicated data?), try
    to send response msg to master lcore, since this multicast message is
    dispatched from master lcore::

      struct dpvs_msg *msg, *xmsg;

      /* send response msg to Master for multicast msg */
      if (DPVS_MSG_MULTICAST == msg_type->mode) {
          xmsg = msg_make(msg->type, msg->seq, DPVS_MSG_UNICAST, cid, msg->reply.len,
                  msg->reply.data);
          if (unlikely(NULL == xmsg)) {
              ret = EDPVS_NOMEM;
              break;
          }
          add_msg_flags(xmsg, DPVS_MSG_F_CALLBACK_FAIL & get_msg_flags(msg));
          msg_send(xmsg, mid, DPVS_MSG_F_ASYNC, NULL);
      }
 
    response is made via msg_make::

      struct dpvs_msg* msg_make(msgid_t type, uint32_t seq,
              DPVS_MSG_MODE mode,
              lcoreid_t cid,
              uint32_t len, const void *data)
      {
          struct dpvs_msg *msg;
          uint32_t flags;
      
          msg  = rte_zmalloc("msg", sizeof(struct dpvs_msg) + len, RTE_CACHE_LINE_SIZE);
          if (unlikely(NULL == msg))
              return NULL;
      
          init_msg_flags(msg);
          flags = get_msg_flags(msg);
          if (flags)
              RTE_LOG(WARNING, MSGMGR, "dirty msg flags: %d\n", flags);
      
          msg->type = type;
          msg->seq = seq;
          msg->mode = mode;
          msg->cid = cid;
          msg->len = len;
          if (len)
              memcpy(msg->data, data, len);
          assert(0 == flags);
      
          return msg;
      }

    and init_msg_flags just initializes spinlock, no any flags set.
    And the new created msg inherits type, seq, mode, cid, len and data(if has)
    from msg.

  - after response msg created, set DPVS_MSG_F_CALLBACK_FAIL and any other
    flags from msg as its flags.

  - next, send (response) msg to lcore via send_msg::

      msg_send(xmsg, mid, DPVS_MSG_F_ASYNC, NULL);

    msg_send will:

      - add caller specified flags as xmsg(send msg) flags, since
        msg_slave_process calls it with DPVS_MSG_F_ASYNC, so it will add
        DPVS_MSG_F_ASYNC to xmsg flags.

        Most caller for send_msg will pass DPVS_MSG_F_ASYNC as flags, but
        only get_lcore_stats in src/netif.c will send 0 as flags, and 0 is not
        an enum flag.

      - check whether xmsg is NULL, or cid is slave lcore id, or cid is not
        found in slave_lcore_mask(which means current lcore is not configured
        for dpvs). If one these condition is true, xmsg will be destroyed via
        __msg_destroy.
      - check xmsg msg_type, if NULL, destroy.
      - update msg_type refcnt via msg_type_put.
      - call rte_ring_enqueue to put msg on ring, if any error returns, call
        __msg_destroy if necessary.
      - per most caller will pass DPVS_MSG_F_ASYNC as flags, so send_msg will
        check case when flags excluding DPVS_MSG_F_ASYNC.

        For such case, it has annotation "asynchronous msg can never set its
        flags after sent (enqueued), because msg consumer may have already
        freed the msg".

        It will set DPVS_MSG_F_STATE_SEND as msg flags. And msg_master_process
        or msg_slave_process will be called to process until msg flags not
        including DPVS_MSG_F_STATE_FIN or DPVS_MSG_F_STATE_DROP.

  - after response msg is sent, __msg_destroy will be called for msg, and 
    msg_type refcnt will be updated via msg_type_put.

For netif_lcore_loop_job_register, it will check whether ctrl_lcore_job is
invalid or already existing, after that, it will call::

    list_add_tail(&lcore_job->list, &netif_lcore_jobs[lcore_job->type]);

where lcore_job is pointer to ctrl_lcore_job, netif_lcore_jobs is a list_head.
lcore_job will be added as tail of netif_lcore_jobs, per netif_lcore_loop_job
structure, they are bidirection chained via netif_lcore_jobs.


register built-in msg type
..........................

Next register_built_in_msg will be called. It initializes a dpvs_msg_type with
type MSG_TYPE_REG, mode DPVS_MSG_UNICAST, unicast_msg_cb msg_type_reg_cb, and
walks throught all lcores, when lcore is enabld with dpdk, register the msg
_type via msg_type_register. And later re-initializes msg_type with
MSG_TYPE_UNREG and msg_type_unreg_cb, and register for all lcores again.


sockopt_init
::::::::::::

What the msg_init do is to initialize the sockopt module.

In function sockopt_init, a stream oriented socket will be created::

    srv_fd = socket(PF_UNIX, SOCK_STREAM, 0);

and it will be set as non-block::

    srv_fd_flags = fcntl(srv_fd, F_GETFL, 0);
    srv_fd_flags |= O_NONBLOCK;
    if (-1 == fcntl(srv_fd, F_SETFL, srv_fd_flags)) {
        RTE_LOG(ERR, MSGMGR, "[%s] Fail to set server socket NONBLOCK\n", __func__);
        return EDPVS_IO;
    }

and the server socket will try to bind and listen on *sockaddr*::

    if (-1 == bind(srv_fd, (struct sockaddr*)&srv_addr, sizeof(srv_addr))) {
        ...
    }
    if (-1 == listen(srv_fd, 1)) {
        ...
    }

where sockaddr will be initialized and assisgned as::

    struct sockaddr_un srv_addr;
    memset(&srv_addr, 0, sizeof(struct sockaddr_un));
    srv_addr.sun_family = AF_UNIX;
    strncpy(srv_addr.sun_path, ipc_unix_domain, sizeof(srv_addr.sun_path) - 1);

where ipc_unix_domain is defined and assigned as::

    char ipc_unix_domain[256];
    memset(ipc_unix_domain, 0, sizeof(ipc_unix_domain));
    strncpy(ipc_unix_domain, UNIX_DOMAIN_DEF, sizeof(ipc_unix_domain) - 1);

and UNIX_DOMAIN_DEF is::

    #define UNIX_DOMAIN_DEF "/var/run/dpvs_ctrl"


Some questions here
```````````````````

About *sockopt_list*, it is defined as::

    static struct list_head sockopt_list;

and where list_head is::

    struct list_head {
            struct list_head *next, *prev;
    };

It will be initilized in sockopt_init via::

    INIT_LIST_HEAD(&sockopt_list);

where INIT_LIST_HEAD is defined as::

    static inline void INIT_LIST_HEAD(struct list_head *list)
    {
            list->next = list;
            list->prev = list;
    }

But I can't see where sockopt_list is going to be used for now.


sockopt_ctl
```````````

New incomming client will be accepted via *accept*::

    int clt_fd;
    struct sockaddr_un clt_addr;

    memset(&clt_addr, 0, sizeof(struct sockaddr_un));
    clt_len = sizeof(clt_addr);

    /* Note: srv_fd is nonblock */
    clt_fd = accept(srv_fd, (struct sockaddr*)&clt_addr, &clt_len);

and client socket is block::

    struct dpvs_sock_msg *msg;

    /* Note: clt_fd is block */
    ret = sockopt_msg_recv(clt_fd, &msg);

and where struct dpvs_sock_msg is defined as::

    struct dpvs_sock_msg {
        uint32_t version;
        sockoptid_t id;
        enum sockopt_type type;
        size_t len;
        char data[0];
    };


sockopt_msg_recv
::::::::::::::::

Its function header is defined as::

    static inline int sockopt_msg_recv(int clt_fd, struct dpvs_sock_msg **pmsg)

and it will called in sockopt_ctl like::

    sockopt_msg_recv(clt_fd, &msg)

where msg is a pointer to struct dpvs_sock_msg. So pmsg is a pointer of struct
dpvs_sock pointer. The reason seems to be:

  1. *msg* is not allocated and initialized in sockopt_ctl, so we only get
     a pointer to dpvs_sock_msg struct.
  2. In C, to modify something passed via parameter, we need it's passed
     via pointer. So parameter in sockopt_msg_recv should be a pointer.
     But since *msg* is a pointer already, but with nothing allocated,
     so *msg* is the object we are going to handle, so we need a pointer
     which point to *msg*.

Another interesting thing is struct dpvs_sock_msg, it has *char data[0]*.
It's just a pointer indeed, to point where data starts. And so, size_t
*len* is necessary.

So in sockopt_msg_recv, message is accept via::

    memset(&msg_hdr, 0, sizeof(msg_hdr));
    res = read(clt_fd, &msg_hdr, sizeof(msg_hdr));

yeps, read a message header first. Then the *msg* will be allocated and
assigned::

    *pmsg = rte_malloc("sockopt_msg",
            sizeof(struct dpvs_sock_msg) + msg_hdr.len, RTE_CACHE_LINE_SIZE);

    msg = *pmsg;
    msg->version = msg_hdr.version;
    msg->id = msg_hdr.id;
    msg->type = msg_hdr.type;
    msg->len = msg_hdr.len;

Its allocated size is sizeof(struct dpvs_sock_msg) + msg_hdr.len, which 
indicates header and data body.

And if message has data::

     if (msg_hdr.len > 0) {
         res = read(clt_fd, msg->data, msg->len);

directly read data to space where *data* point to.


sockopt_get
:::::::::::

In sockopt_ctl, after *sockopt_msg_recv*, sockopt_get will be called next::

    skopt = sockopts_get(msg);

Since *msg* has been allocated and assigned in *sockopt_msg_recv*, and function
sockopt_get just need a value not a reference, so *msg* is passed here, not
its pointer.

In sockopt_get, for *msg->type* in (SOCKOPT_GET, SOCKOPT_SET), it has::

    list_for_each_entry(skopt, &sockopt_list, list) {
        if (judge_id_betw(msg->id, skopt->get_opt_min, skopt->get_opt_max)) {
            ....
            }
            return skopt;
        }
    }

where list_for_each_entry is::

    /**
     * list_for_each_entry  -       iterate over list of given type
     * @pos:        the type * to use as a loop cursor.
     * @head:       the head for your list.
     * @member:     the name of the list_head within the struct.
     */
    #define list_for_each_entry(pos, head, member)                          \
            for (pos = list_first_entry(head, typeof(*pos), member);        \
                 &pos->member != (head);                                    \
                 pos = list_next_entry(pos, member))
    
where skopt and its type is::

    struct dpvs_sockopts *skopt;

    struct dpvs_sockopts {
        uint32_t version;
        struct list_head list;
        sockoptid_t set_opt_min;
        sockoptid_t set_opt_max;
        int (*set)(sockoptid_t opt, const void *in, size_t inlen);
        sockoptid_t get_opt_min;
        sockoptid_t get_opt_max;
        int (*get)(sockoptid_t opt, const void *in, size_t inlen, void **out, size_t *outlen);
    };

Notice the annotation of list_for_each_entry for *member*. So list_head in
dpvs_sockopts is bidirection chain to link all dpvs_sockopts together. 

?? Where do the dpvs_sockopts get initialized? Are they are already in list?

Notice that dpvs_sockopts has two methods, set and get. And *set* and *get*
are pointers which point to a function. So different kind of dpvs_sockopts will
have different functions?

In main, there is no trace about dpvs_sockopts, so it must be some other
functions called before sockopt_ctl, who does something for dpvs_sockopts.
