OVN controller main loop
************************

For my poor experience of ovn-controller, it:

  - monitors relevant changings in OVN SB DB, such as port_binding and
    logical_flows,
  - translates data fetched from OVN SB DB to ovs flow on local chassis
  - accept any packet submitted by ovs vswitch via action controller, and
    do response for that

but how does it main work loop look like? In this note, I will try to dig
for that.

Update: hope I can finish some day, feel sad.
