1. Install Varnish
    ```
    sudo apt install -y varnish
    ```

2. Start Varnish and enable to launch it automatically on System Boot
    ```
    systemctl start varnish
    ```
    ```
    systemctl enable varnish
    ```


3.  Set up varnish to listen to port 80. So, all incoming http connection will connect to varnish:

    A) Edit the ‘DAEMON_OPTS’ line, change the default port 6081 for public address with standard http port 80 as shown below:

    ```
    sudo vim /etc/default/varnish
    ```

    Change the port to 80

    ``` 	
    DAEMON_OPTS="-a :80 \
    -T localhost:6082 \
    -f /etc/varnish/default.vcl \
    -S /etc/varnish/secret \
    -s malloc,256m"
    ```

    B) Also change the port to 80 on varnish.service
    ```
    sudo vim /lib/systemd/system/varnish.service
    ```
    ```
    ExecStart=/usr/sbin/varnishd -j unix,user=vcache -F -a :80 -T localhost:6082 -f /etc/varnish/default.vcl -S /etc/varnish/secret -s malloc,256m
    ```	

4. Point varnish to content server (for e.g. apache). Assume apache is listening to port :8080
	
	```
    cd /etc/varnish
    ```

	*Backup:*
    ```
    cp default.vcl default.vcl.backup
    ```

    *Edit:*

    ```
	sudo vim default.vcl
    ```

    *Change the port to 8080 on following section:*
	 	 	
    **Point to content server.**
    ```
    backend_default {
        .host=”127.0.0.1”;
        .port=”8080”
    }
    ```

5. Reload the systemd service configuration and restart varnish

    ``` 	 	
    sudo systemctl daemon-reload
    ```
    ```
    sudo systemctl restart varnish
    ```


6. Install Apache


7. Change Apache default Port on ports.config:

    ```
    cd /etc/apache2
    ```
	```
    sed -i -e ‘s/80/8080/g’ ports.conf
    ```


8. Change Apache default port on Virtual Host:

	```
    cd /etc/apache2
    ```
	```
    sed -i -e ‘s/80/8080/g’ sites-available/*
    ```


9. Excluding part of page from caching with ESI (Edge side Includes)

    (A) First, enable esi on varnish
    ```
    sub vcl_backend_response { 
      set beresp.do_esi = true;  
    }
    ```


    (B) Second, put the part of a page that need to be excluded from caching between <esi> tags
    ```
    <esi:include src="inc/sidebar.php"/>
    <esi:remove>
      <?php include('inc/sidebar.php'); ?>
      <!-- No ESI! --> 
    </esi:remove>
    ```

    Now, with this on place if esi is enabled on varnish it will use esi:include & if esi is not enabled it will use php include and display "No ESI!" on source code. 


    Source: https://www.smashingmagazine.com/2015/02/using-edge-side-includes-in-varnish/

