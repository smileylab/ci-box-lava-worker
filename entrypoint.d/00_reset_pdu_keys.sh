#!/bin/sh

ssh-keygen -f ~/.ssh/known_hosts -R $LAVA_PDU_SERVER
ssh-keyscan $LAVA_PDU_SERVER >> ~/.ssh/known_hosts
