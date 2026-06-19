# CloudFront Integration Issues: HTTPS, X-Forwarded-Proto & Mixed Content

## Overview

When introducing Amazon CloudFront in front of an existing ALB-based architecture, two classes of issues emerge: incorrect or inconsistent HTTPS detection in backend applications and mixed content errors in frontend when calling backend APIs. These issues are not caused by ALB failure, but by changes in request flow, proxy trust boundaries, and frontend origin perception.

---

## Original Working Architecture (Before CloudFront)

### Request Flow

```
Browser → ALB → NGINX → Backend (PHP/FPM or API)
```

### Behavior

- ALB directly received browser traffic
- Correctly set: `X-Forwarded-Proto: https`
- Backend correctly inferred request scheme
- Frontend and backend operated under consistent origin assumptions

### Results

✅ No mixed content issues  
✅ No HTTPS detection issues  
✅ URLs generated correctly

---

## New Architecture (After Adding CloudFront)

### Request Flow

```
Browser → CloudFront → ALB → NGINX → Backend
```

### Changes Introduced

- Amazon CloudFront became the first entry point (edge layer)
- Additional proxy layer added
- Header propagation dependency created
- New public origin URL (CloudFront domain)

---

## Root Causes of Issues

### Issue 1: X-Forwarded-Proto Inconsistency

**Expected:**
```
X-Forwarded-Proto: https
```

**What Sometimes Happened:**
- Header missing
- Header overwritten
- ALB receiving inconsistent proxy context

**Impact:**

Backend (PHP/NGINX) incorrectly interpreted request as HTTP instead of HTTPS

**Results:**
- Wrong URL generation (`http://` instead of `https://`)
- Redirect issues
- Cookie security issues

### Issue 2: Mixed Content Errors (Frontend)

**Scenario:**

Frontend loads as:
```
https://frontend.com (via CloudFront)
```

But frontend makes API calls like:
```javascript
fetch("http://backend.com/api")
```

**Why This Broke:**

Browser security rule: **HTTPS pages cannot request HTTP resources**

**Results:**
- API calls blocked by browser
- CORS-like errors observed (but root cause was mixed content)

### Issue 3: Changed Origin Context

| Aspect | Before CloudFront | After CloudFront |
|--------|-------------------|------------------|
| Origin perception | Single origin | Frontend origin changed to CloudFront domain |
| URL assumptions | Direct to backend | Environment-based URL assumptions broke |

---

## Why ALB-Only Setup Worked Earlier

Amazon Web Services ALB was the edge proxy, which meant:

- It directly saw browser HTTPS connection
- It reliably set `X-Forwarded-Proto`
- No intermediate CDN layer altered request behavior

---

## Key Misconception Identified

### ❌ Incorrect Assumption

"ALB always knows real user protocol and CloudFront just passes it"

### ✅ Correct Model

- ALB only knows CloudFront → ALB connection protocol
- Browser is never directly visible to ALB
- Protocol truth must be carried via trusted headers

---

## Fixes Applied / Required

### Fix 1: Ensure Correct X-Forwarded-Proto Propagation

**At CloudFront behavior level:**
- Forward required headers
- Preserve Host, X-Forwarded-*

**At ALB level:**
- Ensure HTTPS origin connection from CloudFront

**At NGINX level:**
- Pass headers correctly to backend

### Fix 2: Application-Level Trust of Proxy Headers

Backend must use `X-Forwarded-Proto` to determine scheme, or implement framework-level "trust proxy" configuration.

### Fix 3: Fix Frontend API URLs (CRITICAL)

**Option A (Best Practice):**
```javascript
fetch("/api")
```

**Option B: Use HTTPS Backend**
```javascript
https://backend.com
```

**Option C: Environment-Based Config**
```javascript
API_BASE_URL = "https://backend.com"
```

### Fix 4: Eliminate Mixed Content

Ensure:
- Frontend always HTTPS
- Backend always HTTPS OR same-origin routing
- No hardcoded `http://` URLs

---

## Final Correct Architecture (Best Practice)

```
Browser
  ↓ HTTPS
CloudFront (Edge)
  ↓ HTTPS
ALB
  ↓ HTTP/HTTPS (internal)
NGINX
  ↓
Backend
```

### Requirements

✔ Frontend always HTTPS  
✔ Backend always HTTPS (recommended)  
✔ No HTTP URLs in frontend  
✔ Proxy headers consistently trusted

---

## Key Learnings

1. **CloudFront introduces a new trust boundary** — it becomes the first proxy layer that browsers see
2. **ALB does NOT know browser-level truth** — it only knows the CloudFront → ALB connection protocol
3. **X-Forwarded-Proto is a proxy-derived signal, not real TLS verification** — it must be trusted carefully
4. **Mixed content is a frontend browser security issue, not backend failure** — HTTPS pages cannot request HTTP resources
5. **Application must avoid hardcoded HTTP URLs** — all URLs should be HTTPS or relative paths

---

## Conclusion

The issue was not caused by ALB or backend failure, but by:

- Introduction of CloudFront as a proxy layer
- Break in consistent header propagation assumptions
- Frontend generating HTTP API calls under HTTPS context

The system was stabilized by:

- Enforcing HTTPS consistency
- Trusting proxy headers correctly
- Removing HTTP-based frontend API calls

---

## Interview Tips

When discussing this topic in a DevOps interview:

1. **Emphasize the trust boundary concept** — CloudFront changed where the browser connection terminates
2. **Explain the difference between protocol truth levels** — browser sees HTTPS, but ALB only sees CloudFront → ALB protocol
3. **Highlight the mixed content issue** — this is a browser security feature, not a backend problem
4. **Show the fix priority** — X-Forwarded-Proto propagation is critical; relative URLs are essential
5. **Mention best practice** — end-to-end HTTPS with proper header handling is the safest approach
