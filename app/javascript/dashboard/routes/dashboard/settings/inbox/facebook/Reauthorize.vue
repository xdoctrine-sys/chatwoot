<script>
/* global FB */
import InboxReconnectionRequired from '../components/InboxReconnectionRequired.vue';
import { useAlert } from 'dashboard/composables';

import { loadScript } from 'dashboard/helper/DOMHelpers';
import { buildFacebookLoginScopes } from 'dashboard/helper/facebookScopes';
import * as Sentry from '@sentry/vue';

export default {
  components: {
    InboxReconnectionRequired,
  },
  props: {
    inbox: {
      type: Object,
      required: true,
    },
    // Explicit, admin-triggered Instagram link for an already connected Facebook
    // page inbox. Requests the Instagram scopes on top of the page scopes so the
    // linked instagram_id is stored. Kept out of the default Messenger connect
    // flow on purpose (see chatwoot/chatwoot#14695).
    connectInstagramAccount: {
      type: Boolean,
      default: false,
    },
  },
  data() {
    return {
      // FB.login opens a popup and needs the click's transient activation. The
      // SDK is loaded and initialised on mount so the click-time call resolves
      // within that window; a cold load during the click resolves after the
      // activation has expired and the popup gets blocked.
      isSDKReady: false,
      isSDKFailed: false,
      isConnecting: false,
      // Non-reactive cache of the in-flight SDK setup so repeated calls reuse it.
      sdkSetupPromise: null,
    };
  },
  computed: {
    inboxId() {
      return this.inbox.id;
    },
    facebookLoginScopes() {
      return buildFacebookLoginScopes({
        includeInstagramScopes:
          this.connectInstagramAccount || !!this.inbox.instagram_id,
      });
    },
    isBusy() {
      // Keep the action disabled until the SDK is ready, and while a connection
      // attempt is in flight (guards against duplicate clicks).
      return this.isConnecting || !this.isSDKReady;
    },
    bannerActionLabel() {
      // After a load failure there is no usable retry (see preloadSdk), so the
      // action is dropped and the banner asks for a page reload instead.
      if (this.isSDKFailed) return null;
      return this.connectInstagramAccount
        ? this.$t('INBOX_MGMT.FACEBOOK_INSTAGRAM.CONNECT_ACTION')
        : null;
    },
    bannerDescription() {
      if (this.isSDKFailed) return this.$t('INBOX_MGMT.FB_SDK_LOAD_FAILED');
      return this.connectInstagramAccount
        ? this.$t('INBOX_MGMT.FACEBOOK_INSTAGRAM.CONNECT_DESCRIPTION')
        : null;
    },
  },
  mounted() {
    window.fbAsyncInit = this.runFBInit;
    this.preloadSdk().catch(() => {
      // Failure is surfaced by the banner's reload instruction.
    });
  },
  methods: {
    runFBInit() {
      FB.init({
        appId: window.chatwootConfig.fbAppId,
        xfbml: true,
        version: window.chatwootConfig.fbApiVersion,
        status: true,
      });
      window.fbSDKLoaded = true;
      FB.AppEvents.logPageView();
    },

    async loadFBsdk() {
      return loadScript('https://connect.facebook.net/en_US/sdk.js', {
        id: 'facebook-jssdk',
      });
    },

    // Idempotent: loads and initialises the SDK once and caches the promise.
    preloadSdk() {
      if (!this.sdkSetupPromise) {
        this.sdkSetupPromise = this.loadFBsdk()
          .then(() => {
            this.runFBInit();
            this.isSDKReady = true;
          })
          .catch(error => {
            // loadScript keeps the failed <script> in the DOM and only marks
            // success, so a retried loadScript would re-attach listeners to a
            // dead element and leave the next promise pending forever. The
            // failure is therefore terminal here and the banner asks for a
            // page reload rather than offering a retry that cannot work.
            this.isSDKFailed = true;
            this.handleSdkError(error);
            throw error;
          });
      }
      return this.sdkSetupPromise;
    },

    handleSdkError(error) {
      if (error.name === 'ScriptLoaderError') {
        // if the error was related to script loading, we show a toast
        useAlert(this.$t('INBOX_MGMT.DETAILS.ERROR_FB_LOADING'));
      } else {
        // if the error was anything else, we capture it and show a toast
        Sentry.captureException(error);
        useAlert(this.$t('INBOX_MGMT.DETAILS.ERROR_FB_AUTH'));
      }
    },

    async startLogin() {
      if (this.isConnecting) return;
      this.isConnecting = true;
      try {
        // Resolves immediately when the SDK preloaded on mount.
        await this.preloadSdk();
        this.tryFBlogin(); // make an attempt to login
      } catch (error) {
        this.isConnecting = false;
      }
    },

    tryFBlogin() {
      FB.login(
        response => {
          if (response.status === 'connected') {
            this.reauthorizeFBPage(response.authResponse.accessToken);
          } else {
            // Either the person is logged into Facebook but not the app, or is
            // not logged into Facebook at all — both need the same alert.
            this.isConnecting = false;
            useAlert(this.$t('INBOX_MGMT.DETAILS.ERROR_FB_AUTH'));
          }
        },
        {
          scope: this.facebookLoginScopes,
          auth_type: 'reauthorize',
        }
      );
    },
    async reauthorizeFBPage(omniauthToken) {
      try {
        await this.$store.dispatch('inboxes/reauthorizeFacebookPage', {
          omniauthToken,
          inboxId: this.inboxId,
        });
        useAlert(this.$t('INBOX_MGMT.FACEBOOK_REAUTHORIZE.MESSAGE_SUCCESS'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.FACEBOOK_REAUTHORIZE.MESSAGE_ERROR'));
      } finally {
        this.isConnecting = false;
      }
    },
  },
};
</script>

<template>
  <InboxReconnectionRequired
    class="mx-6"
    :is-loading="isBusy"
    :action-label="bannerActionLabel"
    :description="bannerDescription"
    @reauthorize="startLogin"
  />
</template>

<style lang="scss" scoped>
.fb--login {
  img {
    max-width: 240px;
    padding: 1rem 0;
  }
}
</style>
