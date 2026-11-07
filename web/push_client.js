// Push notification client bridge (scaffold for ADR-057, loaded dynamically in PR D).
// Injected and executed only when user explicitly interacts with notification settings.
(function () {
  'use strict';
  window.__churchPortalPush = {
    isSupported: function () {
      return (
        'Notification' in window &&
        'serviceWorker' in navigator &&
        'PushManager' in window
      );
    },
    permission: function () {
      return 'Notification' in window ? Notification.permission : 'unsupported';
    },
    requestPermission: function () {
      if (!('Notification' in window)) {
        return Promise.resolve('unsupported');
      }
      return Notification.requestPermission();
    }
  };
})();
