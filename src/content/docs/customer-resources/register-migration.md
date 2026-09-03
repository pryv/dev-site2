---
title: 'Pryv.io register migration (v1 only)'
---


> **⚠️ This page applies to Pryv.io v1 only.**
>
> In Pryv.io v2 the register service no longer exists — registration, DNS and the admin endpoints are all built into the single core binary. There is nothing separate to migrate.
>
> - To move a v2 core to a new machine, follow the [core migration](/customer-resources/core-migration/) guide.
> - To scale out a v2 single-node install, follow the [single-node to multi-core upgrade](/customer-resources/single-node-to-cluster/) guide.
> - To **upgrade an existing v1 deployment to v2** (exporting v1 user data and importing it into a fresh v2 install), use the [`dev-migrate-v1-v2`](https://github.com/pryv/dev-migrate-v1-v2) toolkit.
>
> The procedure below is preserved as a historical reference for operators still running the v1 (pre-2026) multi-service topology.

This guide describes how to migrate the register role of Pryv.io v1 to a new machine.

The register migration procedure only takes into account the master registers. If you need to migrate a slave, simply deploy a new one and replication will take care of the data migration.  

We copy the data from the old master register to the new one, set the old register to proxy to the new one and enable replication between the two so they are synchronized during the DNS propagation phase.


## Table of contents <!-- omit in toc -->

1. [Setup *dest* machine](#setup-dest-machine)
2. [Transfer data](#transfer-data)
   1. [Transfer config data](#transfer-config-data)
   2. [Transfer user data and fetch docker images](#transfer-user-data-and-fetch-docker-images)
   3. [Fix permissions and boot services on *dest*](#fix-permissions-and-boot-services-on-dest)
3. [Set NGINX redirection for register on *source*](#set-nginx-redirection-for-register-on-source)
4. [Reload NGINX on *source*](#reload-nginx-on-source)
5. [Set the *source* register as replica of the *dest* register through a SSH tunnel](#set-the-source-register-as-replica-of-the-dest-register-through-a-ssh-tunnel)
6. [Update Name servers](#update-name-servers)
7. [Verify](#verify)
8. [Finalize](#finalize)


## Setup *dest* machine

We assume that you have installed `docker` and `docker-compose` on the *dest* machine and have authenticated yourself with our private Docker repository.


## Transfer data

We will be transfering data using rsync, therefore, we setup a pair of keys for this:

1. Create an SSH key pair using the following command:  

  ```bash
  ssh-keygen -t rsa -b 4096 -C "migration@remote"
  ```
  
2. Copy the private one to `${PATH_TO_PRIVATE_KEY}` in *source*  

3. Add the public one in `~/.ssh/authorized_keys` on *dest*  

4. Shutdown services on *source* to prevent new information from arriving: `${PRYV_CONF_ROOT}/stop-pryv`  


### Transfer config data

5. Transfer config leader, on *source*, run:  

   ```bash
   time rsync --verbose --copy-links \
        --archive --compress -e \
     "ssh -i ${PATH_TO_PRIVATE_KEY}" \
        ${PRYV_CONF_ROOT}/config-leader \
        ${USERNAME}@${DEST_MACHINE}:${PRYV_CONF_ROOT}/config-leader/
   ```

   You may have to go via your home user directory on *dest* first if permission issues arise.  

6. Transfer config follower, on *source*, run:  

   ```bash
   time rsync --verbose --copy-links \
        --archive --compress -e \
     "ssh -i ${PATH_TO_PRIVATE_KEY}" \
        ${PRYV_CONF_ROOT}/config-follower \
        ${USERNAME}@${DEST_MACHINE}:${PRYV_CONF_ROOT}/config-follower/
   ```
   
   (Same comment as previous step about permissions.)  

7. Fetch docker images on *dest* by running:  

   ```bash
   ${PRYV_CONF_ROOT}/run-config-follower
   ${PRYV_CONF_ROOT}/run-pryv
   ```
   
8. Shutdown Pryv services on *dest* prior to transferring user data:  

   ```bash
   ${PRYV_CONF_ROOT}/stop-pryv
   ```


### Transfer user data and fetch docker images

9. Transfer Redis data: on *source*, run:  

   ```bash
   time rsync --verbose --copy-links \
     --archive --compress --delete -e \
     "ssh -i ${PATH_TO_PRIVATE_KEY}" \
     ${PRYV_CONF_ROOT}/pryv/redis/data \
     ${USERNAME}@${DEST_MACHINE}:${PRYV_CONF_ROOT}/pryv/redis/data/
   ```
   
   (Same comment as previous step about permissions.)  


### Fix permissions and boot services on *dest*

10. On *dest*, run `${PRYV_CONF_ROOT}/ensure-permissions-reg-master` script to help with enforcing correct permissions on data and log folders.  

11. Then setup the config and boot services on *dest*:  

    ```bash
    ${PRYV_CONF_ROOT}/run-pryv
    ```

If you wish to reactivate service on the *source* machine, simply reboot the stopped services: `${PRYV_CONF_ROOT}/run-pryv`.  


## Set NGINX redirection for register on *source*

Since the DNS changes will take some time to come into effect, the NGINX process on *source* will be set to proxy to the *dest* machine.
The following steps describe the configuration changes to make NGINX proxy calls to the *dest* register. It is advised to comment out the old setting inline using `#` in order to rollback easily in case of need.

- In `${PRYV_CONF_ROOT}/pryv/nginx/conf/site-443.conf`, Replace the following:

  ```nginx
  upstream register_server {
    server register:9000 max_fails=3 fail_timeout=30s;
  }

  upstream mail_server {
    server mail:9000 max_fails=3 fail_timeout=30s;
  }

  upstream leader_server {
    server config-leader:7000 max_fails=3 fail_timeout=30s;
  }

  upstream admin_panel_server {
    server admin_panel:80;
  }
  ```

  with

  ```nginx
  upstream register_server {
    server ${DEST_REGISTER_IP_ADDRESS}:443;
  }

  upstream mail_server {
    server ${DEST_REGISTER_IP_ADDRESS}:443;
  }

  upstream leader_server {
    server ${DEST_REGISTER_IP_ADDRESS}:443;
  }

  upstream admin_panel_server {
    server ${DEST_REGISTER_IP_ADDRESS}:80;
  }
  ```

- In the same file, change the proxy protocol from `http` to `https`:

  - Change: `http://register_server` to `https://register_server`
  - Change: `http://mail_server` to `https://mail_server`
  - Change: `http://leader_server` to `https://leader_server`
  - Change: `http://admin_panel_server` to `https://admin_panel_server`


## Reload NGINX on *source*

Run `${PRYV_CONF_ROOT}/run-pryv`

As we are currently using docker-compose to specify the mounted volumes (containing the NGINX config), we just boot all services, even if they will unused as NGINX is proxying to the *dest* machine.


## Set the *source* register as replica of the *dest* register through a SSH tunnel

As DNS requests might still be routed to the old machine, we need to keep its database updated.

1. On the *dest* machine, open the Redis container port 6379 to localhost: Add `- "127.0.0.1:6379:6379"` to the `ports` section of the `redis` service in the `${PRYV_CONF_ROOT}/pryv/pryv.yml` docker-compose file and reboot it running `${PRYV_CONF_ROOT}/restart-pryv`
2. Copy the private key generated earlier to the *source* register in `${PRYV_CONF_ROOT}/pryv/redis/conf` so it is mounted in the container upon startup
3. Set *source* register as replica of *dest* register and add the following to *source* register's redis config file `${PRYV_CONF_ROOT}/pryv/redis/conf/redis.conf`: `replicaof localhost 4567`
4. Reboot services on *source*: `${PRYV_CONF_ROOT}/restart-pryv`
5. On the *source* register, enter the redis container (`docker exec -ti pryvio_redis bash`), open a SSH tunnel: run `ssh -i ${PATH_TO_PRIVATE_KEY} -L 4567:127.0.0.1:6379 root@${DEST_REG_HOSTNAME} -N`.


## Update Name servers

In your hosting provider (or your own system), set the name servers to the domain name associate to your Pryv.io platform as the *dest* register machines.

Update the `NAME_SERVER_ENTRIES` platform parameter accordingly


## Verify

Run a DNS query on the *dest* register machines and verify that they contain the same data as the *source* ones.

Run `dig @{DEST_REG_MASTER_IP_ADDRESS} USERNAME.DOMAIN` and `dig @{DEST_REG_SLAVE_IP_ADDRESS} USERNAME.DOMAIN`


## Finalize

After some time, all DNS requests will be directed to the *dest* register machines. To verify this, take a look at the logs on the *sources* of the `dns` and `register` containers and ensure that they have served no request in ~24 hours.
