#
# This is an example VCL file for Varnish.
#
# It does not do anything by default, delegating control to the
# builtin VCL. The builtin VCL is called when there is no explicit
# return statement.
#
# See the VCL chapters in the Users Guide at https://www.varnish-cache.org/docs/
# and https://www.varnish-cache.org/trac/wiki/VCLExamples for more examples.

# Marker to tell the VCL compiler that this VCL has been adapted to the
# new 4.0 format.
vcl 4.0;

# Default backend definition. Set this to point to your content server.
backend default {
    .host = "127.0.0.1";
    .port = "8080";

    #Use varnish cache for High Availability with backend polling
    #Continue serving cache content if the backend is unreachable.
    .probe = {
    #.url = "/"; # short easy way (GET /)
    # We prefer to only do a HEAD /
    .request =
      "HEAD / HTTP/1.1"
      "Host: localhost"
      "Connection: close"
      "User-Agent: Varnish Health Probe";

        .interval  = 5s; # check the health of each backend every 5 seconds
        .timeout   = 1s; # timing out after 1 second.
        .window    = 5;  # If 3 out of the last 5 polls succeeded the backend is considered healthy, otherwise it will be marked as sick
        .threshold = 3;
    }

    .first_byte_timeout     = 300s;   # How long to wait before we receive a first byte from our backend?
    .connect_timeout        = 5s;     # How long to wait for a backend connection?
    .between_bytes_timeout  = 2s;     # How long to wait between bytes received from our backend?
}

sub vcl_recv {
    # Happens before we check if we have this in cache already.
    #
    # Typically you clean up the request here, removing cookies you don't need,
    # rewriting the request, etc.

    #Cookies are preventing cache hits. Stripping cookies (Cache-Control: no-cache)
    if (!(req.url ~ "^/admin/")) {
        unset req.http.cookie;
    }
}

sub vcl_backend_response {
    # Happens after we have read the response headers from the backend.
    #
    # Here you clean the response headers, removing silly Set-Cookie headers
    # and other mistakes your backend does.

    if (beresp.ttl < 12h) {
          unset beresp.http.cookie;
          unset beresp.http.Set-Cookie;

          # Setting TTL variable object to 12h. Can be in seconds (120s), minutes(2m) or hours(2h).
          ## Will save the cache version for 12h
          set beresp.ttl = 12h;

          # choose to only do this for certain urls (wrap it in ( if req.url ~ "" ) logic)
          unset beresp.http.Cache-Control;
          #set beresp.http.Cache-Control = "public"; # do we need this
    }

    # 24h allows the backend to be down for 24 hour without any impact to website users.
    # Allow stale content, in case the backend goes down.
    # Make Varnish keep all objects for 12 hours beyond their TTL
    set beresp.grace = 24h;
}

sub vcl_deliver {
    # Happens when we have all the pieces we need, and are about to send the
    # response to the client.
    #
    # You can do accounting or modifying the final object here.

    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }

    # Note that obj.hits behaviour changed in 4.0, now it counts per objecthead, not per object, and obj.hits may not
    # be reset in some cases where bans are in use.

    # So take hits with a grain of salt
    set resp.http.X-Cache-Hits = obj.hits;
}
