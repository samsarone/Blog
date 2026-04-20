const url = require('url');
const path = require('path');
const debug = require('@tryghost/debug')('web:shared:mw:url-redirects');
const urlUtils = require('../../../../shared/url-utils');

const _private = {};

_private.redirectUrl = ({redirectTo, query, pathname}) => {
    const parts = url.parse(redirectTo);

    // CASE: ensure we always add a trailing slash to reduce the number of redirects
    // e.g. you are redirected from example.com/ghost to admin.example.com/ghost and Ghost would detect a missing slash and redirect you to /ghost/
    // Exceptions: asset requests
    if (!pathname.match(/\/$/) && !path.extname(pathname)) {
        pathname += '/';
    }

    return url.format({
        protocol: parts.protocol,
        hostname: parts.hostname,
        port: parts.port,
        pathname,
        query
    });
};

/**
 * Takes care of
 *
 * 1. required SSL redirects
 * 2. redirect to the correct admin url
 */
_private.getAdminRedirectUrl = ({requestedHost, requestedUrl, queryParameters, secure}) => {
    const siteUrl = urlUtils.urlFor('home', true);
    const adminUrl = urlUtils.urlFor('admin', true);
    const siteHost = url.parse(siteUrl).host;
    const adminHost = url.parse(adminUrl).host;

    debug('getAdminRedirectUrl', requestedHost, requestedUrl, adminHost, siteHost);

    // CASE: always canonicalize the admin host to the configured admin URL host.
    // This avoids mixed-host session origins such as samsar.one vs www.samsar.one.
    if (adminHost !== requestedHost) {
        debug('redirect because admin host does not match');

        return _private.redirectUrl({
            redirectTo: adminUrl,
            pathname: requestedUrl,
            query: queryParameters
        });
    }

    // CASE: configured admin url is HTTPS, but request is HTTP
    if (urlUtils.isSSL(adminUrl) && !secure) {
        debug('redirect because protocol does not match');

        return _private.redirectUrl({
            redirectTo: adminUrl,
            pathname: requestedUrl,
            query: queryParameters
        });
    }
};

/**
 * Takes care of
 *
 * 1. required SSL redirects
 */
_private.getFrontendRedirectUrl = ({requestedHost, requestedUrl, queryParameters, secure}) => {
    const siteUrl = urlUtils.urlFor('home', true);
    const siteHost = url.parse(siteUrl).host;

    debug('getFrontendRedirectUrl', requestedHost, requestedUrl, siteUrl);

    if (siteHost !== requestedHost) {
        debug('redirect because host does not match canonical site host');

        return _private.redirectUrl({
            redirectTo: siteUrl,
            pathname: requestedUrl,
            query: queryParameters
        });
    }

    // CASE: configured canonical url is HTTPS, but request is HTTP, redirect to requested host + SSL
    if (urlUtils.isSSL(siteUrl) && !secure) {
        debug('redirect because protocol does not match');

        return _private.redirectUrl({
            redirectTo: `https://${requestedHost}`,
            pathname: requestedUrl,
            query: queryParameters
        });
    }
};

_private.redirect = function urlRedirectsRedirect(req, res, next, redirectFn) {
    const redirectUrl = redirectFn({
        requestedHost: req.vhost ? req.vhost.host : req.get('host'),
        requestedUrl: url.parse(req.originalUrl || req.url).pathname,
        queryParameters: req.query,
        secure: req.secure
    });

    if (redirectUrl) {
        debug(`url redirect to: ${redirectUrl}`);
        return urlUtils.redirect301(res, redirectUrl);
    }

    debug('no url redirect');
    next();
};

const frontendRedirect = function frontendRedirect(req, res, next) {
    _private.redirect(req, res, next, _private.getFrontendRedirectUrl);
};

const adminRedirect = function adminRedirect(req, res, next) {
    _private.redirect(req, res, next, _private.getAdminRedirectUrl);
};

module.exports.frontendSSLRedirect = frontendRedirect;
module.exports.adminSSLAndHostRedirect = adminRedirect;
