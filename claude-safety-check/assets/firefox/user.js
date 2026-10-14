// Dedicated Claude Firefox profile. Keep this profile separate from daily browsing.
// Location, WebRTC, camera, microphone, and notifications are disabled by default.
user_pref("geo.enabled", false);
user_pref("permissions.default.geo", 2);
user_pref("media.peerconnection.enabled", false);
user_pref("permissions.default.camera", 2);
user_pref("permissions.default.microphone", 2);
user_pref("permissions.default.desktop-notification", 2);

// Fail closed through the selected DigiLink local proxy port.
user_pref("network.proxy.type", 1);
user_pref("network.proxy.http", "127.0.0.1");
user_pref("network.proxy.http_port", __PROXY_PORT__);
user_pref("network.proxy.ssl", "127.0.0.1");
user_pref("network.proxy.ssl_port", __PROXY_PORT__);
user_pref("network.proxy.share_proxy_settings", true);
user_pref("network.proxy.no_proxies_on", "localhost, 127.0.0.1");
user_pref("network.proxy.failover_direct", false);
user_pref("network.proxy.allow_bypass", false);

user_pref("dom.security.https_only_mode", true);
user_pref("privacy.globalprivacycontrol.enabled", true);
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.trackingprotection.socialtracking.enabled", true);
user_pref("network.cookie.cookieBehavior", 5);
user_pref("network.prefetch-next", false);
user_pref("network.dns.disablePrefetch", true);
user_pref("network.predictor.enabled", false);
user_pref("network.http.speculative-parallel-limit", 0);

user_pref("identity.fxaccounts.enabled", false);
user_pref("signon.rememberSignons", false);
user_pref("browser.formfill.enable", false);
user_pref("extensions.formautofill.addresses.enabled", false);
user_pref("extensions.formautofill.creditCards.enabled", false);
user_pref("browser.search.suggest.enabled", false);
user_pref("browser.urlbar.suggest.searches", false);

user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("dom.private-attribution.submission.enabled", false);

user_pref("browser.startup.page", 1);
user_pref("browser.startup.homepage", "https://claude.ai/");
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.aboutwelcome.enabled", false);

