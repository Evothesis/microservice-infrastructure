
(function() {
  // Configuration - Update the endpoint URL with your actual API Gateway URL
  var config = {
    endpoint: 'https://5tepk9mq26.execute-api.us-west-1.amazonaws.com/prod/collect',
    sessionTimeout: 30 * 60 * 1000, // 30 minutes
    trackClicks: true,
    trackForms: true,
    trackPageViews: true,
    trackScrollDepth: true,
    sampleRate: 100, // Track 100% of visitors
    
    // Activity-based batching configuration
    inactivityTimeout: 60 * 1000, // Send batch after 1 minute of inactivity
    maxBatchSize: 50, // Increased since batches will be larger
    batchOnExit: true, // Send remaining batch on page exit
    
    // Scroll tracking configuration
    scrollMilestones: [25, 50, 75, 100], // Percentage milestones to track
    scrollThrottle: 100 // Throttle scroll events (ms)
  };

  // Auto-detect site ID from hostname
  var getSiteId = function() {
    var hostname = window.location.hostname;
    // Remove common prefixes and convert to clean site ID
    var cleanHostname = hostname.replace(/^(www\.|m\.|mobile\.)/, '');
    return cleanHostname.replace(/\./g, '-');
  };

  // Update config with detected site ID
  config.siteId = getSiteId();

  // Generate unified session ID (shared across tabs)
  var getSessionId = function() {
    var currentTime = Date.now();
    var sessionId = localStorage.getItem('_ts_session_id');
    var sessionStart = parseInt(localStorage.getItem('_ts_session_start') || '0');
    var lastActivity = parseInt(localStorage.getItem('_ts_last_activity') || '0');
    
    // Check if session has expired (30 minutes of inactivity across ALL tabs)
    var sessionExpired = (currentTime - lastActivity) > config.sessionTimeout;
    
    if (!sessionId || sessionExpired) {
      // Create new session
      sessionId = 'sess_' + Math.random().toString(36).substring(2, 15) + 
                  Math.random().toString(36).substring(2, 15);
      localStorage.setItem('_ts_session_id', sessionId);
      localStorage.setItem('_ts_session_start', currentTime.toString());
      
      console.log('[Tracking] New session created:', sessionId);
    }
    
    // Update last activity time
    localStorage.setItem('_ts_last_activity', currentTime.toString());
    
    // Also store in sessionStorage for tab-specific tracking if needed
    sessionStorage.setItem('_ts_tab_session_id', sessionId);
    sessionStorage.setItem('_ts_tab_start', currentTime.toString());
    
    return sessionId;
  };

  // Parse URL parameters
  var getUrlParams = function(url) {
    var params = {};
    var urlObj;
    
    try {
      urlObj = new URL(url);
    } catch (e) {
      return params;
    }
    
    var searchParams = urlObj.searchParams;
    if (searchParams) {
      searchParams.forEach(function(value, key) {
        params[key.toLowerCase()] = value;
      });
    } else {
      // Fallback for older browsers
      var queryString = urlObj.search.substring(1);
      var pairs = queryString.split('&');
      for (var i = 0; i < pairs.length; i++) {
        var pair = pairs[i].split('=');
        if (pair.length === 2) {
          params[decodeURIComponent(pair[0]).toLowerCase()] = decodeURIComponent(pair[1]);
        }
      }
    }
    
    return params;
  };

  // Extract UTM parameters
  var getUtmParams = function() {
    var params = getUrlParams(window.location.href);
    return {
      utm_source: params.utm_source || null,
      utm_medium: params.utm_medium || null,
      utm_campaign: params.utm_campaign || null,
      utm_content: params.utm_content || null,
      utm_term: params.utm_term || null
    };
  };

  // Extract campaign tracking parameters (Facebook, Google, etc.)
  var getCampaignParams = function() {
    var params = getUrlParams(window.location.href);
    return {
      // Facebook
      fbclid: params.fbclid || null,
      fb_source: params.fb_source || null,
      fb_ref: params.fb_ref || null,
      
      // Google
      gclid: params.gclid || null,
      gclsrc: params.gclsrc || null,
      dclid: params.dclid || null,
      
      // Microsoft/Bing
      msclkid: params.msclkid || null,
      
      // Twitter
      twclid: params.twclid || null,
      
      // LinkedIn
      li_fat_id: params.li_fat_id || null,
      
      // TikTok
      ttclid: params.ttclid || null,
      
      // Pinterest
      epik: params.epik || null,
      
      // Snapchat
      sclid: params.sclid || null,
      
      // Generic tracking
      ref: params.ref || null,
      source: params.source || null,
      medium: params.medium || null,
      campaign: params.campaign || null
    };
  };

  // Classify referrer domain
  var classifyReferrer = function(referrer) {
    if (!referrer || referrer === '') {
      return { type: 'direct', platform: null, category: 'direct' };
    }
    
    var hostname;
    try {
      hostname = new URL(referrer).hostname.toLowerCase();
    } catch (e) {
      return { type: 'unknown', platform: hostname, category: 'other' };
    }
    
    // Social media platforms
    var socialPlatforms = {
      'facebook.com': 'facebook',
      'm.facebook.com': 'facebook',
      'l.facebook.com': 'facebook',
      'lm.facebook.com': 'facebook',
      'instagram.com': 'instagram',
      'twitter.com': 'twitter',
      'x.com': 'twitter',
      't.co': 'twitter',
      'linkedin.com': 'linkedin',
      'youtube.com': 'youtube',
      'm.youtube.com': 'youtube',
      'youtu.be': 'youtube',
      'tiktok.com': 'tiktok',
      'pinterest.com': 'pinterest',
      'pin.it': 'pinterest',
      'snapchat.com': 'snapchat',
      'reddit.com': 'reddit'
    };
    
    // Search engines
    var searchEngines = {
      'google.com': 'google',
      'google.co.uk': 'google',
      'google.ca': 'google',
      'google.com.au': 'google',
      'bing.com': 'bing',
      'yahoo.com': 'yahoo',
      'duckduckgo.com': 'duckduckgo',
      'yandex.com': 'yandex',
      'baidu.com': 'baidu'
    };
    
    // Check for matches
    for (var domain in socialPlatforms) {
      if (hostname === domain || hostname.endsWith('.' + domain)) {
        return { type: 'social', platform: socialPlatforms[domain], category: 'social' };
      }
    }
    
    for (var domain in searchEngines) {
      if (hostname === domain || hostname.endsWith('.' + domain)) {
        return { type: 'search', platform: searchEngines[domain], category: 'organic' };
      }
    }
    
    // Check if it's the same domain (internal)
    if (hostname === window.location.hostname) {
      return { type: 'internal', platform: hostname, category: 'internal' };
    }
    
    // Default to referral
    return { type: 'referral', platform: hostname, category: 'referral' };
  };

  // Determine traffic source classification
  var getTrafficSource = function() {
    var utmParams = getUtmParams();
    var campaignParams = getCampaignParams();
    var referrer = document.referrer;
    var referrerData = classifyReferrer(referrer);
    
    var source = 'direct';
    var medium = 'none';
    var campaign = null;
    var category = 'direct';
    
    // UTM parameters take priority
    if (utmParams.utm_source) {
      source = utmParams.utm_source;
      medium = utmParams.utm_medium || 'unknown';
      campaign = utmParams.utm_campaign;
      
      // Classify based on UTM medium
      if (medium.match(/^(cpc|ppc|paid|adwords|google_ads)$/i)) {
        category = 'paid_search';
      } else if (medium.match(/^(display|banner|cpm|retargeting)$/i)) {
        category = 'display';
      } else if (medium.match(/^(social|facebook|instagram|twitter|linkedin)$/i)) {
        category = 'paid_social';
      } else if (medium.match(/^(email|newsletter)$/i)) {
        category = 'email';
      } else {
        category = 'campaign';
      }
    }
    // Campaign parameters (Facebook, Google, etc.)
    else if (campaignParams.fbclid) {
      source = 'facebook';
      medium = 'cpc';
      category = 'paid_social';
    }
    else if (campaignParams.gclid) {
      source = 'google';
      medium = 'cpc';
      category = 'paid_search';
    }
    else if (campaignParams.msclkid) {
      source = 'bing';
      medium = 'cpc';
      category = 'paid_search';
    }
    // Referrer-based classification
    else if (referrerData.type !== 'direct') {
      source = referrerData.platform || 'unknown';
      category = referrerData.category;
      
      if (referrerData.type === 'social') {
        medium = 'social';
        category = 'organic_social';
      } else if (referrerData.type === 'search') {
        medium = 'organic';
        category = 'organic_search';
      } else {
        medium = 'referral';
        category = 'referral';
      }
    }
    
    return {
      source: source,
      medium: medium,
      campaign: campaign,
      category: category,
      referrer: referrer,
      referrerDomain: referrerData.platform,
      utmParams: utmParams,
      campaignParams: campaignParams
    };
  };

  // Get attribution data
  var getAttributionData = function() {
    var currentAttribution = getTrafficSource();
    var storedAttribution = sessionStorage.getItem('_ts_attribution');
    
    if (!storedAttribution) {
      // First visit in session - store current attribution
      sessionStorage.setItem('_ts_attribution', JSON.stringify(currentAttribution));
      return {
        firstTouch: currentAttribution,
        currentTouch: currentAttribution,
        touchCount: 1
      };
    } else {
      // Returning visit - increment touch count
      var firstTouch = JSON.parse(storedAttribution);
      var touchCount = parseInt(sessionStorage.getItem('_ts_touch_count') || '1') + 1;
      sessionStorage.setItem('_ts_touch_count', touchCount.toString());
      
      return {
        firstTouch: firstTouch,
        currentTouch: currentAttribution,
        touchCount: touchCount
      };
    }
  };

  // Get basic browser/device data
  var getBrowserData = function() {
    return {
      userAgent: navigator.userAgent,
      language: navigator.language || navigator.browserLanguage || 'unknown',
      screenWidth: window.screen ? window.screen.width : 0,
      screenHeight: window.screen ? window.screen.height : 0,
      viewportWidth: window.innerWidth || 0,
      viewportHeight: window.innerHeight || 0,
      devicePixelRatio: window.devicePixelRatio || 1,
      timezone: Intl.DateTimeFormat ? Intl.DateTimeFormat().resolvedOptions().timeZone : 'unknown'
    };
  };

  // Get scroll data for events
  var getCurrentScrollData = function() {
    var scrollTop = window.pageYOffset || document.documentElement.scrollTop || document.body.scrollTop || 0;
    var windowHeight = window.innerHeight || document.documentElement.clientHeight || 0;
    var documentHeight = Math.max(
      document.body.scrollHeight || 0,
      document.body.offsetHeight || 0,
      document.documentElement.clientHeight || 0,
      document.documentElement.scrollHeight || 0,
      document.documentElement.offsetHeight || 0
    );
    
    var scrollableHeight = documentHeight - windowHeight;
    var scrollPercentage = scrollableHeight > 0 ? Math.round((scrollTop / scrollableHeight) * 100) : 100;
    scrollPercentage = Math.min(100, Math.max(0, scrollPercentage));
    
    return {
      scrollPercentage: scrollPercentage,
      maxScrollPercentage: scrollDepthTracking.maxScroll,
      milestonesReached: Object.keys(scrollDepthTracking.milestones).filter(function(key) {
        return scrollDepthTracking.milestones[key];
      }).map(Number).sort(function(a, b) { return a - b; }),
      scrollTop: scrollTop,
      documentHeight: documentHeight,
      windowHeight: windowHeight
    };
  };

  // Activity-based event batching system
  var eventBatch = [];
  var inactivityTimer = null;
  var lastActivityTime = Date.now();

  // Activity detection and timer management
  var activityManager = {
    
    // Track user activity and reset inactivity timer
    recordActivity: function() {
      lastActivityTime = Date.now();
      this.resetInactivityTimer();
    },
    
    // Reset the inactivity timer
    resetInactivityTimer: function() {
      if (inactivityTimer) {
        clearTimeout(inactivityTimer);
      }
      
      // Always set timer when there are events, even if it's the first one
      if (eventBatch.length >= 0) { // Changed from > 0 to >= 0
        inactivityTimer = setTimeout(function() {
          console.log('[Tracking] Sending batch due to 1 minute inactivity');
          sendBatch();
        }, config.inactivityTimeout);
      }
    },
    
    // Set up activity listeners
    initActivityListeners: function() {
      var self = this;
      
      // Mouse activity
      document.addEventListener('mousemove', function() {
        self.recordActivity();
      }, { passive: true });
      
      document.addEventListener('mousedown', function() {
        self.recordActivity();
      }, { passive: true });
      
      // Keyboard activity
      document.addEventListener('keydown', function() {
        self.recordActivity();
      }, { passive: true });
      
      // Scroll activity (already throttled by scroll tracking)
      document.addEventListener('scroll', function() {
        self.recordActivity();
      }, { passive: true });
      
      // Touch activity (mobile)
      document.addEventListener('touchstart', function() {
        self.recordActivity();
      }, { passive: true });
      
      // Window focus/blur
      window.addEventListener('focus', function() {
        self.recordActivity();
      });
      
      // Page visibility changes
      document.addEventListener('visibilitychange', function() {
        if (!document.hidden) {
          self.recordActivity();
        }
      });
    }
  };

  // Send batched events
  var sendBatch = function() {
    if (eventBatch.length === 0) return;
    
    if (Math.random() * 100 > config.sampleRate) {
      eventBatch = [];
      if (inactivityTimer) {
        clearTimeout(inactivityTimer);
        inactivityTimer = null;
      }
      return;
    }
    
    var payload = {
      eventType: 'batch',
      timestamp: new Date().toISOString(),
      sessionId: getSessionId(),
      visitorId: getVisitorId(),
      siteId: config.siteId,
      batchMetadata: {
        eventCount: eventBatch.length,
        batchStartTime: eventBatch.length > 0 ? eventBatch[0].timestamp : null,
        batchEndTime: eventBatch.length > 0 ? eventBatch[eventBatch.length - 1].timestamp : null,
        activityDuration: lastActivityTime - (eventBatch.length > 0 ? new Date(eventBatch[0].timestamp).getTime() : lastActivityTime)
      },
      events: eventBatch
    };
    
    console.log('[Tracking] Sending activity-based batch:', eventBatch.length + ' events', payload);
    
    // Send batch
    try {
      if (window.fetch) {
        fetch(config.endpoint, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify(payload),
          keepalive: true,
          mode: 'no-cors'
        }).catch(function(error) {
          console.error('[Tracking] Batch fetch error:', error);
        });
      } else {
        // Fallback to XHR for older browsers
        var xhr = new XMLHttpRequest();
        xhr.open('POST', config.endpoint, true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.send(JSON.stringify(payload));
      }
    } catch(e) {
      console.error('[Tracking] Error sending batch:', e);
    }
    
    // Clear batch and timer
    eventBatch = [];
    if (inactivityTimer) {
      clearTimeout(inactivityTimer);
      inactivityTimer = null;
    }
  };

  // Get minimal data for lightweight events
  var getMinimalData = function() {
    return {
      timestamp: new Date().toISOString(),
      sessionId: getSessionId(),
      visitorId: getVisitorId(),
      siteId: config.siteId,
      url: window.location.href,
      path: window.location.pathname
    };
  };

  // Add event to batch (for activity-based sending)
  var addToBatch = function(eventType, eventData) {
    var event = {
      eventType: eventType,
      timestamp: new Date().toISOString(),
      sessionId: getSessionId(),
      visitorId: getVisitorId(),
      siteId: config.siteId,
      url: window.location.href,
      path: window.location.pathname,
      eventData: eventData || {}
    };
    
    eventBatch.push(event);
    
    // Record activity for user interactions to reset inactivity timer
    var userActivityEvents = ['click', 'scroll', 'scroll_depth', 'form_submit'];
    if (userActivityEvents.indexOf(eventType) !== -1) {
      activityManager.recordActivity();
    }
    
    // Send batch if it reaches max size (safety mechanism)
    if (eventBatch.length >= config.maxBatchSize) {
      console.log('[Tracking] Sending batch due to max size reached');
      sendBatch();
    }
  };

  // Generate visitor ID
  var getVisitorId = function() {
    var visitorId = localStorage.getItem('_ts_visitor_id');
    if (!visitorId) {
      visitorId = 'vis_' + Math.random().toString(36).substring(2, 15) + 
                  Math.random().toString(36).substring(2, 15);
      localStorage.setItem('_ts_visitor_id', visitorId);
    }
    return visitorId;
  };

  // Send immediate event (for important events like pageview)
  var sendImmediate = function(eventType, eventData) {
    if (Math.random() * 100 > config.sampleRate) {
      return;
    }
    
    var payload = {
      eventType: eventType,
      timestamp: new Date().toISOString(),
      sessionId: getSessionId(),
      visitorId: getVisitorId(),
      siteId: config.siteId,
      url: window.location.href,
      path: window.location.pathname,
      eventData: eventData || {}
    };
    
    // Add rich data for pageview events
    if (eventType === 'pageview') {
      payload.attribution = getAttributionData();
      payload.browser = getBrowserData();
      payload.scroll = getCurrentScrollData();
      payload.page = {
        title: document.title,
        url: window.location.href,
        path: window.location.pathname,
        referrer: document.referrer || 'direct',
        queryParams: window.location.search,
        hash: window.location.hash
      };
    }
    
    // Add session data for page_exit events
    if (eventType === 'page_exit') {
      payload.scroll = getCurrentScrollData();
    }
    
    console.log('[Tracking] Sending immediate:', eventType, payload);
    
    try {
      if (window.fetch) {
        fetch(config.endpoint, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify(payload),
          keepalive: true,
          mode: 'no-cors'
        }).catch(function(error) {
          console.error('[Tracking] Immediate fetch error:', error);
        });
      } else {
        var xhr = new XMLHttpRequest();
        xhr.open('POST', config.endpoint, true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.send(JSON.stringify(payload));
      }
    } catch(e) {
      console.error('[Tracking] Error sending immediate event:', e);
    }
  };

  // Determine if event should be batched or sent immediately
  var sendData = function(eventType, eventData) {
    var immediateEvents = ['pageview', 'page_exit', 'form_submit'];
    
    if (immediateEvents.indexOf(eventType) !== -1) {
      sendImmediate(eventType, eventData);
    } else {
      addToBatch(eventType, eventData);
    }
  };

  // Track page view
  var trackPageView = function() {
    if (config.trackPageViews) {
      // Store page start time for exit calculations
      sessionStorage.setItem('_ts_page_start', Date.now().toString());
      sendData('pageview');
    }
  };

  // Track clicks
  var trackClicks = function() {
    if (config.trackClicks) {
      document.addEventListener('click', function(event) {
        var element = event.target;
        var tagName = element.tagName.toLowerCase();
        var classes = '';
        
        if (element.classList) {
          var classArray = [];
          for (var i = 0; i < element.classList.length; i++) {
            classArray.push(element.classList[i]);
          }
          classes = classArray.join(' ');
        } else if (element.className) {
          classes = element.className;
        }
        
        sendData('click', {
          tagName: tagName,
          classes: classes,
          id: element.id,
          href: element.href || '',
          text: (element.innerText || element.textContent || '').substring(0, 100),
          position: {
            x: event.clientX,
            y: event.clientY
          }
        });
      });
    }
  };

  // Track form submissions
  var trackForms = function() {
    if (config.trackForms) {
      document.addEventListener('submit', function(event) {
        var form = event.target;
        var formData = {};
        var excludedFields = ['password', 'credit', 'card', 'cvv', 'ssn', 'social'];
        
        for (var i = 0; i < form.elements.length; i++) {
          var element = form.elements[i];
          
          if (!element.name || ['input', 'textarea', 'select'].indexOf(element.tagName.toLowerCase()) === -1) {
            continue;
          }
          
          var isExcluded = false;
          for (var j = 0; j < excludedFields.length; j++) {
            var term = excludedFields[j];
            if (element.name.toLowerCase().indexOf(term) !== -1 || 
                (element.id && element.id.toLowerCase().indexOf(term) !== -1)) {
              isExcluded = true;
              break;
            }
          }
          
          if (isExcluded) {
            formData[element.name] = '[REDACTED]';
          } else {
            if (element.type === 'checkbox' || element.type === 'radio') {
              if (element.checked) {
                formData[element.name] = element.value;
              }
            } else {
              formData[element.name] = element.value;
            }
          }
        }
        
        sendData('form_submit', {
          formId: form.id || 'unknown',
          formAction: form.action || window.location.href,
          formMethod: form.method || 'get',
          formData: formData
        });
      });
    }
  };

  // Scroll depth tracking
  var scrollDepthTracking = {
    maxScroll: 0,
    milestones: {},
    lastScrollTime: 0,
    
    init: function() {
      if (!config.trackScrollDepth) return;
      
      var self = this;
      
      // Initialize milestones
      config.scrollMilestones.forEach(function(milestone) {
        self.milestones[milestone] = false;
      });
      
      // Throttled scroll handler
      var throttledScroll = this.throttle(function() {
        self.trackScroll();
      }, config.scrollThrottle);
      
      window.addEventListener('scroll', throttledScroll, { passive: true });
      
      // Track initial position (in case page loads already scrolled)
      setTimeout(function() {
        self.trackScroll();
      }, 1000);
    },
    
    trackScroll: function() {
      var scrollTop = window.pageYOffset || document.documentElement.scrollTop || document.body.scrollTop || 0;
      var windowHeight = window.innerHeight || document.documentElement.clientHeight || 0;
      var documentHeight = Math.max(
        document.body.scrollHeight || 0,
        document.body.offsetHeight || 0,
        document.documentElement.clientHeight || 0,
        document.documentElement.scrollHeight || 0,
        document.documentElement.offsetHeight || 0
      );
      
      // Calculate scroll percentage
      var scrollableHeight = documentHeight - windowHeight;
      var scrollPercentage = scrollableHeight > 0 ? Math.round((scrollTop / scrollableHeight) * 100) : 100;
      
      // Ensure percentage is within bounds
      scrollPercentage = Math.min(100, Math.max(0, scrollPercentage));
      
      // Update max scroll if this is deeper
      if (scrollPercentage > this.maxScroll) {
        this.maxScroll = scrollPercentage;
        
        // Send scroll progress update (throttled)
        var currentTime = Date.now();
        if (currentTime - this.lastScrollTime > 2000) { // Only every 2 seconds
          sendData('scroll', {
            scrollPercentage: scrollPercentage,
            scrollTop: scrollTop,
            documentHeight: documentHeight,
            windowHeight: windowHeight
          });
          this.lastScrollTime = currentTime;
        }
      }
      
      // Check milestones
      var self = this;
      config.scrollMilestones.forEach(function(milestone) {
        if (!self.milestones[milestone] && scrollPercentage >= milestone) {
          self.milestones[milestone] = true;
          
          // Calculate time to reach this milestone
          var pageStart = parseInt(sessionStorage.getItem('_ts_page_start') || Date.now());
          var timeToMilestone = Date.now() - pageStart;
          
          sendData('scroll_depth', {
            milestone: milestone,
            timeToMilestone: timeToMilestone,
            scrollPercentage: scrollPercentage,
            scrollTop: scrollTop,
            documentHeight: documentHeight,
            windowHeight: windowHeight
          });
          
          console.log('[Tracking] Scroll milestone reached:', milestone + '%');
        }
      });
    },
    
    // Simple throttle function
    throttle: function(func, limit) {
      var inThrottle;
      return function() {
        var args = arguments;
        var context = this;
        if (!inThrottle) {
          func.apply(context, args);
          inThrottle = true;
          setTimeout(function() { inThrottle = false; }, limit);
        }
      };
    },
    
    // Reset for new page
    reset: function() {
      this.maxScroll = 0;
      this.lastScrollTime = 0;
      var self = this;
      config.scrollMilestones.forEach(function(milestone) {
        self.milestones[milestone] = false;
      });
    }
  };

  // Track page exit with activity-based batch cleanup
  var trackExit = function() {
    window.addEventListener('beforeunload', function() {
      var startTime = parseInt(sessionStorage.getItem('_ts_page_start') || Date.now());
      var timeSpent = Date.now() - startTime;
      
      console.log('[Tracking] Page exit - checking for remaining batch events:', eventBatch.length);
      
      // Send any remaining batched events immediately on exit
      if (eventBatch.length > 0) {
        console.log('[Tracking] Sending remaining batch on exit:', eventBatch.length + ' events');
        
        var batchPayload = {
          eventType: 'batch',
          timestamp: new Date().toISOString(),
          sessionId: getSessionId(),
          visitorId: getVisitorId(),
          siteId: config.siteId,
          batchMetadata: {
            eventCount: eventBatch.length,
            batchStartTime: eventBatch.length > 0 ? eventBatch[0].timestamp : null,
            batchEndTime: eventBatch.length > 0 ? eventBatch[eventBatch.length - 1].timestamp : null,
            sentOnExit: true
          },
          events: eventBatch
        };
        
        if (navigator.sendBeacon) {
          navigator.sendBeacon(config.endpoint, JSON.stringify(batchPayload));
        } else {
          // Fallback for browsers without sendBeacon
          try {
            var xhr = new XMLHttpRequest();
            xhr.open('POST', config.endpoint, false); // Synchronous for page exit
            xhr.setRequestHeader('Content-Type', 'application/json');
            xhr.send(JSON.stringify(batchPayload));
          } catch(e) {
            console.error('[Tracking] Failed to send exit batch:', e);
          }
        }
      }
      
      // Clear activity timer
      if (inactivityTimer) {
        clearTimeout(inactivityTimer);
      }
      
      // Send page exit event immediately
      var exitData = {
        eventType: 'page_exit',
        timestamp: new Date().toISOString(),
        sessionId: getSessionId(),
        visitorId: getVisitorId(),
        siteId: config.siteId,
        url: window.location.href,
        path: window.location.pathname,
        eventData: { timeSpent: timeSpent }
      };
      
      if (navigator.sendBeacon) {
        navigator.sendBeacon(config.endpoint, JSON.stringify(exitData));
      } else {
        try {
          var xhr = new XMLHttpRequest();
          xhr.open('POST', config.endpoint, false);
          xhr.setRequestHeader('Content-Type', 'application/json');
          xhr.send(JSON.stringify(exitData));
        } catch(e) {
          console.error('[Tracking] Failed to send exit event:', e);
        }
      }
    });
  };

  // Initialize tracking with cross-tab session management
  var init = function() {
    if (typeof window === 'undefined' || typeof document === 'undefined') {
      console.warn('[Tracking] Browser environment not detected');
      return;
    }
    
    if (!window.localStorage || !window.sessionStorage) {
      console.warn('[Tracking] Browser does not support localStorage or sessionStorage');
      return;
    }
    
    if (navigator.doNotTrack === '1' || window.doNotTrack === '1') {
      console.info('[Tracking] Respecting Do Not Track setting');
      return;
    }
    
    try {
      // Initialize session (this will either continue existing or create new)
      var sessionId = getSessionId();
      console.log('[Tracking] Session ID:', sessionId);
      
      // Set up periodic activity updates to maintain session across tabs
      var activityUpdateInterval = setInterval(function() {
        if (document.hasFocus()) {
          localStorage.setItem('_ts_last_activity', Date.now().toString());
        }
      }, 10000); // Update every 10 seconds when tab is active
      
      // Store interval for cleanup
      window._ts_activity_interval = activityUpdateInterval;
      
      // Listen for focus/blur to track tab activity
      window.addEventListener('focus', function() {
        localStorage.setItem('_ts_last_activity', Date.now().toString());
      });
      
      window.addEventListener('visibilitychange', function() {
        if (!document.hidden) {
          localStorage.setItem('_ts_last_activity', Date.now().toString());
        }
      });
      
      // Initialize activity tracking for batching
      activityManager.initActivityListeners();
      
      // Initialize scroll depth tracking
      scrollDepthTracking.init();
      
      trackPageView();
      trackClicks();
      trackForms();
      trackExit();
      
      console.info('[Tracking] Initialized successfully with activity-based batching');
    } catch (error) {
      console.error('[Tracking] Error during initialization:', error);
    }
  };

  // Run initialization
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();