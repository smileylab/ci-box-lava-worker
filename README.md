# Important Notice

ci-box-lava-worker has moved away from origin ci-box (Loic Poulain) setup

The new mechanism follows Kernel-CI docker (https://github.com/kernelci/lava-docker.git) setup

* configs contains all the configuration files used by lava-worker, configuration files are modifed by ../ci-box-gen.py depending on the ci-box-conf.yaml settings
* entrypoint.d contains start-up scripts when lava-worker starts
* lava-patch contains any patch files that is necessary to patch the lava-worker python code.

