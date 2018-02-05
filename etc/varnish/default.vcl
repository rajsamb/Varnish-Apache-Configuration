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

    call devicedetect;

    # Cookies are preventing cache hits. Stripping cookies (Cache-Control: no-cache)
    if (!(req.url ~ "^/admin/")) {
        unset req.http.cookie;
    }

    # Some generic URL manipulation, useful for all templates that follow
    # First remove the Google Analytics added parameters, useless for our backend
    if (req.url ~ "(\?|&)(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=") {
        set req.url = regsuball(req.url, "&(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=([A-z0-9_\-\.%25]+)", "");
        set req.url = regsuball(req.url, "\?(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=([A-z0-9_\-\.%25]+)", "?");
    set req.url = regsub(req.url, "\?&", "?");
        set req.url = regsub(req.url, "\?$", "");
    }

    # Remove any Google Analytics based cookies
    set req.http.Cookie = regsuball(req.http.Cookie, "__utm.=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "_ga=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "_gat=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "utmctr=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "utmcmd.=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "utmccn.=[^;]+(; )?", "");

    # Some generic cookie manipulation, useful for all templates that follow
    # Remove the "has_js" cookie
    set req.http.Cookie = regsuball(req.http.Cookie, "has_js=[^;]+(; )?", "");

    # Remove DoubleClick offensive cookies
    set req.http.Cookie = regsuball(req.http.Cookie, "__gads=[^;]+(; )?", "");

    # Remove the Quant Capital cookies (added by some plugin, all __qca)
    set req.http.Cookie = regsuball(req.http.Cookie, "__qc.=[^;]+(; )?", "");

    # Remove the AddThis cookies
    set req.http.Cookie = regsuball(req.http.Cookie, "__atuv.=[^;]+(; )?", "");

    # Remove a ";" prefix in the cookie if present
    set req.http.Cookie = regsuball(req.http.Cookie, "^;\s*", "");

    # Are there cookies left with only spaces or that are empty?
    if (req.http.cookie ~ "^\s*$") {
        unset req.http.cookie;
    }

    if (req.http.Cache-Control ~ "(?i)no-cache") {
        #if (req.http.Cache-Control ~ "(?i)no-cache" && client.ip ~ editors) { # create the acl editors if you want to restrict the Ctrl-F5
        # http://varnish.projects.linpro.no/wiki/VCLExampleEnableForceRefresh
        # Ignore requests via proxy caches and badly behaved crawlers
        # like msnbot that send no-cache with every request.

        if (! (req.http.Via || req.http.User-Agent ~ "(?i)bot" || req.http.X-Purge)) {
            #set req.hash_always_miss = true; # Doesn't seems to refresh the object in the cache
            return (purge); # Couple this with restart in vcl_purge and X-Purge header to avoid loops
        }
    }

    # Large static files are delivered directly to the end-user without
    # waiting for Varnish to fully read the file first.
    # Varnish 4 fully supports Streaming, so set do_stream in vcl_backend_response()
    if (req.url ~ "^[^?]*\.(7z|avi|bz2|flac|flv|gz|mka|mkv|mov|mp3|mp4|mpeg|mpg|ogg|ogm|opus|rar|tar|tgz|tbz|txz|wav|webm|xz|zip)(\?.*)?$") {
        unset req.http.Cookie;
        return (hash);
    }

    # Remove all cookies for static files
    # A valid discussion could be held on this line: do you really need to cache static files that don't cause load? Only if you have memory left.
    # Sure, there's disk I/O, but chances are your OS will already have these files in their buffers (thus memory).
    # Before you blindly enable this, have a read here: https://ma.ttias.be/stop-caching-static-files/
    if (req.url ~ "^[^?]*\.(7z|avi|bmp|bz2|css|csv|doc|docx|eot|flac|flv|gif|gz|ico|jpeg|jpg|js|less|mka|mkv|mov|mp3|mp4|mpeg|mpg|odt|otf|ogg|ogm|opus|pdf|png|ppt|pptx|rar|rtf|svg|svgz|swf|tar|tbz|tgz|ttf|txt|txz|wav|webm|webp|woff|woff2|xls|xlsx|xml|xz|zip)(\?.*)?$") {
        unset req.http.Cookie;
        return (hash);
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

    # Enable cache for all static files
    # The same argument as the static caches from above: monitor your cache size, if you get data nuked out of it, consider giving up the static file cache.
    # Before you blindly enable this, have a read here: https://ma.ttias.be/stop-caching-static-files/
    if (bereq.url ~ "^[^?]*\.(7z|avi|bmp|bz2|css|csv|doc|docx|eot|flac|flv|gif|gz|ico|jpeg|jpg|js|less|mka|mkv|mov|mp3|mp4|mpeg|mpg|odt|otf|ogg|ogm|opus|pdf|png|ppt|pptx|rar|rtf|svg|svgz|swf|tar|tbz|tgz|ttf|txt|txz|wav|webm|webp|woff|woff2|xls|xlsx|xml|xz|zip)(\?.*)?$") {
        unset beresp.http.set-cookie;
    }

    # Large static files are delivered directly to the end-user without
    # waiting for Varnish to fully read the file first.
    # Varnish 4 fully supports Streaming, so use streaming here to avoid locking.
    if (bereq.url ~ "^[^?]*\.(7z|avi|bz2|flac|flv|gz|mka|mkv|mov|mp3|mp4|mpeg|mpg|ogg|ogm|opus|rar|tar|tgz|tbz|txz|wav|webm|xz|zip)(\?.*)?$") {
        unset beresp.http.set-cookie;
        set beresp.do_stream = true;  # Check memory usage it'll grow in fetch_chunksize blocks (128k by default) if the backend doesn't send a Content-Length header, so only enable it for big objects
    }
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

sub vcl_hash {
    if (req.http.X-UA-Device) {
	    hash_data(req.http.X-UA-Device);
    }
}

sub devicedetect {
    unset req.http.X-UA-Device;
    set req.http.X-UA-Device = "pc";

    # Handle that a cookie may override the detection alltogether.
    if (req.http.Cookie ~ "(?i)X-UA-Device-force") {
        /* ;?? means zero or one ;, non-greedy to match the first. */
        set req.http.X-UA-Device = regsub(req.http.Cookie, "(?i).*X-UA-Device-force=([^;]+);??.*", "\1");
        /* Clean up our mess in the cookie header */
        set req.http.Cookie = regsuball(req.http.Cookie, "(^|; ) *X-UA-Device-force=[^;]+;? *", "\1");
        /* If the cookie header is now empty, or just whitespace, unset it. */
        if (req.http.Cookie ~ "^ *$") { unset req.http.Cookie; }
    } else {
        if (req.http.User-Agent ~ "\(compatible; Googlebot-Mobile/2.1; \+http://www.google.com/bot.html\)" ||
            (req.http.User-Agent ~ "(Android|iPhone)" && req.http.User-Agent ~ "\(compatible.?; Googlebot/2.1.?; \+http://www.google.com/bot.html") ||
            (req.http.User-Agent ~ "(iPhone|Windows Phone)" && req.http.User-Agent ~ "\(compatible; bingbot/2.0; \+http://www.bing.com/bingbot.htm")) {
            set req.http.X-UA-Device = "mobile-bot";
        } elsif (req.http.User-Agent ~ "(?i)(ads|google|bing|msn|yandex|baidu|ro|career|seznam|)bot" ||
            req.http.User-Agent ~ "(?i)(baidu|jike|symantec)spider" ||
            req.http.User-Agent ~ "(?i)scanner" ||
            req.http.User-Agent ~ "(?i)(web)crawler") {
            set req.http.X-UA-Device = "bot";
        } elsif (req.http.User-Agent ~ "(?i)ipad") {
            set req.http.X-UA-Device = "tablet-ipad";
        } elsif (req.http.User-Agent ~ "(?i)ip(hone|od)") {
            set req.http.X-UA-Device = "mobile-iphone";
        }
        /* how do we differ between an android phone and an android tablet?
           http://stackoverflow.com/questions/5341637/how-do-detect-android-tablets-in-general-useragent */
        elsif (req.http.User-Agent ~ "(?i)android.*(mobile|mini)") {
            set req.http.X-UA-Device = "mobile-android";
        }
        // android 3/honeycomb was just about tablet-only, and any phones will probably handle a bigger page layout.
        elsif (req.http.User-Agent ~ "(?i)android 3") {
            set req.http.X-UA-Device = "tablet-android";
        }
        /* Opera Mobile */
        elsif (req.http.User-Agent ~ "Opera Mobi") {
            set req.http.X-UA-Device = "mobile-smartphone";
        }
        // May very well give false positives towards android tablets. Suggestions welcome.
        elsif (req.http.User-Agent ~ "(?i)android") {
            set req.http.X-UA-Device = "tablet-android";
        } elsif (req.http.User-Agent ~ "PlayBook; U; RIM Tablet") {
            set req.http.X-UA-Device = "tablet-rim";
        } elsif (req.http.User-Agent ~ "hp-tablet.*TouchPad") {
            set req.http.X-UA-Device = "tablet-hp";

        } elsif (req.http.User-Agent ~ "Kindle/3") {
            set req.http.X-UA-Device = "tablet-kindle";
        } elsif (
            req.http.User-Agent ~ "Touch.+Tablet PC" ||
            req.http.User-Agent ~ "Windows NT [0-9.]+; ARM;"
        ) {
            set req.http.X-UA-Device = "tablet-microsoft";
        } elsif (req.http.User-Agent ~ "Mobile.+Firefox") {
            set req.http.X-UA-Device = "mobile-firefoxos";
        } elsif (req.http.User-Agent ~ "^HTC" ||
            req.http.User-Agent ~ "Fennec" ||
            req.http.User-Agent ~ "IEMobile" ||
            req.http.User-Agent ~ "BlackBerry" ||
            req.http.User-Agent ~ "BB10.*Mobile" ||
            req.http.User-Agent ~ "GT-.*Build/GINGERBREAD" ||
            req.http.User-Agent ~ "SymbianOS.*AppleWebKit") {
            set req.http.X-UA-Device = "mobile-smartphone";
        } elsif (req.http.User-Agent ~ "(?i)symbian" ||
            req.http.User-Agent ~ "(?i)^sonyericsson" ||
            req.http.User-Agent ~ "(?i)^nokia" ||
            req.http.User-Agent ~ "(?i)^samsung" ||
            req.http.User-Agent ~ "(?i)^lg" ||
            req.http.User-Agent ~ "(?i)bada" ||
            req.http.User-Agent ~ "(?i)blazer" ||
            req.http.User-Agent ~ "(?i)cellphone" ||
            req.http.User-Agent ~ "(?i)iemobile" ||
            req.http.User-Agent ~ "(?i)midp-2.0" ||
            req.http.User-Agent ~ "(?i)u990" ||
            req.http.User-Agent ~ "(?i)netfront" ||
            req.http.User-Agent ~ "(?i)opera mini" ||
            req.http.User-Agent ~ "(?i)palm" ||
            req.http.User-Agent ~ "(?i)nintendo wii" ||
            req.http.User-Agent ~ "(?i)playstation portable" ||
            req.http.User-Agent ~ "(?i)portalmmm" ||
            req.http.User-Agent ~ "(?i)proxinet" ||
            req.http.User-Agent ~ "(?i)sonyericsson" ||
            req.http.User-Agent ~ "(?i)symbian" ||
            req.http.User-Agent ~ "(?i)windows\ ?ce" ||
            req.http.User-Agent ~ "(?i)winwap" ||
            req.http.User-Agent ~ "(?i)eudoraweb" ||
            req.http.User-Agent ~ "(?i)htc" ||
            req.http.User-Agent ~ "(?i)240x320" ||
            req.http.User-Agent ~ "(?i)avantgo")
		{
            set req.http.X-UA-Device = "mobile-generic";
		}
	}
}

