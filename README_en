# Introduction

This project uses the open-source project [clash](https://github.com/Dreamacro/clash) as its core program, combined with scripts to achieve a simple proxy functionality.

The primary purpose is to address the slow download speeds of resources such as GitHub on servers.

<br>

# Important Notes

- It is recommended to run this project as the root user or with sudo privileges.
- If you encounter issues during use, please check the existing [issues](https://github.com/wanhebin/clash-for-linux/issues) first.
- Before submitting a new issue, replace any sensitive information (e.g., subscription URLs) in your submission.
- This project is based on the configuration integration of [clash](https://github.com/Dreamacro/clash) and [yacd](https://github.com/haishanh/yacd). For detailed configurations, please refer to the original projects.
- This project does not provide any subscription information. You need to prepare your own Clash subscription URL.
- Before running, manually edit the `CLASH_URL` variable in the `.env` file; otherwise, the project will not function properly.
- Currently tested on RHEL and Debian-based Linux systems. Other systems may require minor script modifications.
- Supports x86_64/aarch64 platforms.

> **Note**: If you encounter issues that you cannot resolve independently while using this project, prioritize checking the [Issues](https://github.com/wanhebin/clash-for-linux/issues) for solutions. Due to limited free time, repeated responses to questions already answered in "resolved" issues may not be provided.

<br>

# Usage Guide

## Download the Project

Clone the project repository:

```bash
$ git clone https://github.com/wanhebin/clash-for-linux.git
```

Navigate to the project directory and edit the `.env` file to modify the `CLASH_URL` variable.

```bash
$ cd clash-for-linux
$ vim .env
```

> **Note:** The `CLASH_SECRET` variable in the `.env` file defines a custom Clash Secret. If left blank, the script will automatically generate a random string.

<br>

## Start the Program

Run the `start.sh` script directly.

- Navigate to the project directory:

```bash
$ cd clash-for-linux
```

- Run the startup script:

```bash
$ sudo bash start.sh

Checking subscription URL...
Clash subscription URL is accessible!                         [  OK  ]

Downloading Clash configuration file...
Configuration file config.yaml downloaded successfully!      [  OK  ]

Starting Clash service...
Service started successfully!                                [  OK  ]

Clash Dashboard access URL: http://<ip>:9090/ui
Secret: xxxxxxxxxxxxx

Execute the following command to load environment variables: source /etc/profile.d/clash.sh

Execute the following command to enable the system proxy: proxy_on

To temporarily disable the system proxy, execute: proxy_off

```

Run the following commands to load the environment variables and enable the system proxy:

```bash
$ source /etc/profile.d/clash.sh
$ proxy_on
```

- Check service ports:

```bash
$ netstat -tln | grep -E '9090|789.'
tcp        0      0 127.0.0.1:9090          0.0.0.0:*               LISTEN     
tcp6       0      0 :::7890                 :::*                    LISTEN     
tcp6       0      0 :::7891                 :::*                    LISTEN     
tcp6       0      0 :::7892                 :::*                    LISTEN
```

- Check environment variables:

```bash
$ env | grep -E 'http_proxy|https_proxy'
http_proxy=http://127.0.0.1:7890
https_proxy=http://127.0.0.1:7890
```

If the above steps complete successfully, the Clash service has started, and you can now enjoy high-speed GitHub resource downloads.

<br>

## Restart the Program

To modify the Clash configuration, edit the `conf/config.yaml` file and run the `restart.sh` script to restart the service.

> **Note:** 
> The `restart.sh` script does not update subscription information.

<br>

## Stop the Program

- Navigate to the project directory:

```bash
$ cd clash-for-linux
```

- Stop the service:

```bash
$ sudo bash shutdown.sh

Service stopped successfully. Execute the following command to disable the system proxy: proxy_off
```

Disable the system proxy:

```bash
$ proxy_off
```

Then check the program's ports, processes, and `http_proxy|https_proxy` environment variables. If none are active, the service has stopped correctly.

<br>

## Clash Dashboard

- Access Clash Dashboard:

Open the URL output after successfully running `start.sh` in a browser, e.g., http://192.168.0.1:9090/ui.

- Log in to the management interface:

Enter `http://<ip>:9090` in the `API Base URL` field and the `Secret` displayed during the startup in the `Secret(optional)` field. Click "Add" and select the address you just entered to configure settings via the browser.

- More Tutorials:

The Clash Dashboard uses the [yacd](https://github.com/haishanh/yacd) project. For detailed usage instructions, refer to the yacd project.

<br>

# Common Issues

1. On some Linux systems, the default shell `/bin/sh` is changed to `dash`, causing script errors (e.g., `-en [ OK ]`). Use `bash xxx.sh` to run the scripts.

2. If proxy nodes do not appear in the UI, the issue is likely due to the provider's Clash configuration file being base64 encoded or not conforming to Clash configuration standards. This may allow the script to run but will prevent environment variable checks from displaying any information.

   This project includes functionality to automatically identify and convert Clash configuration files. If it still fails, you may need to manually convert the subscription address via self-hosting or third-party platforms (not recommended due to potential privacy risks). To diagnose specific issues, refer to `logs/clash.log`.

4. If the program log shows `error: unsupported rule type RULE-SET`, consult the official [WIKI](https://github.com/Dreamacro/clash/wiki/FAQ#error-unsupported-rule-type-rule-set) for solutions.
