# This is a basic VCL configuration file for varnish.  See the vcl(7)
# man page for details on VCL syntax and semantics.

${backends}
${director}
acl purge {
    "localhost"; # this is bad if your proxy runs on localhost and proxies PURGEs
${purgehosts}
}

# TODO:
# -----
# * Every anonymous page should be cached, if even for only a few minutes.

sub vcl_recv {
    set req.grace = 120s;
    ${virtual_hosting}

    if (req.request == "PURGE") {
        if (!client.ip ~ purge) {
            error 405 "Not allowed.";
        }
        purge_url(req.url);
        error 200 "Purged";
    }

    call not_get_or_head;

    if (req.http.If-None-Match) {
        pass; # ETag. Avoid for anything cachable.
    }

    if (req.url ~ "createObject") {
        pass;
    }

    call normalize_accept_encoding;
    call annotate_request;

    lookup;
}

sub not_get_or_head {
    # From the default vcl
    if (req.request != "GET" &&
        req.request != "HEAD" &&
        req.request != "PUT" &&
        req.request != "POST" &&
        req.request != "TRACE" &&
        req.request != "OPTIONS" &&
        req.request != "DELETE") {
        /* Non-RFC2616 or CONNECT which is weird. */
        pipe;
    }
    if (req.request != "GET" && req.request != "HEAD") {
        /* We only deal with GET and HEAD by default */
        pass;
    }
}

sub normalize_accept_encoding {
    if (req.http.Accept-Encoding) {
        if (req.url ~ "\.(jpe?g|png|gif|swf|pdf|gz|tgz|bz2|tbz|zip)$" || req.url ~ "/image_[^/]*$") {
            # No point in compressing these
            remove req.http.Accept-Encoding;
        } elsif (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } else {
            remove req.http.Accept-Encoding;
        }
    }
}

sub annotate_request {
    if (!(req.http.Authorization || req.http.cookie ~ "(^|; )__ac=")) {
        set req.http.X-Anonymous = "true";
    }
}

sub vcl_pipe {
    # This is not necessary if you do not do any request rewriting.
    set req.http.connection = "close";
}

sub vcl_fetch {
    set obj.grace = 120s;
    if (!obj.cacheable) {${header_fetch_notcacheable}
        pass;
    }
    if (obj.http.Set-Cookie) {${header_fetch_setcookie}
        pass;
    }
    if (obj.http.Cache-Control ~ "(private|no-cache|no-store)") {${header_fetch_cachecontrol}
        pass;
    }
    if (!req.http.X-Anonymous && !obj.http.Cache-Control ~ "public") {${header_fetch_auth}
        pass;
    }
    ${header_fetch_insert}
}

sub vcl_deliver {
    call rewrite_age;
    call rewrite_s_maxage;
}

sub rewrite_age {
    if (resp.http.Age) {
        # By definition we have a fresh object
        set resp.http.X-Varnish-Age = resp.http.Age;
        set resp.http.Age = "0";
    }
}

sub rewrite_s_maxage {
    # rewrite s-maxage as intermediary proxies cannot be purged
    # XXX Can this go in vcl_fetch (and operate on obj)?
    if (resp.http.Cache-Control ~ "s-maxage") {
        set resp.http.Cache-Control = regsub(resp.http.Cache-Control, "s-maxage=[0-9]+", "s-maxage=0");
    }
}

#sub rewrite_maxage {
#    if (req.http.X-Anonymous && obj.http.Cache-Control ~ "max-age=0") {
#        # rewrite maxage so anonymous users' browsers cache for 5 minutes
#        set obj.http.Cache-Control = regsub(obj.http.Cache-Control, "max-age=0", "max-age=300");
#        remove obj.http.Expires;
#    }
#}
