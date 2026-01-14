# Complete Breaking Changes: Struts 6.0.0 → 6.7.4

## Summary
This document lists ALL breaking changes when upgrading from Struts 6.0.0 to 6.7.4 (the last Java 8 compatible version).

---

## 🔴 CRITICAL BREAKING CHANGES (Will cause compile errors)

### 1. **Package Migration: Aware Interfaces**
**Impact:** HIGH - Will cause "package does not exist" compilation errors

All `*Aware` interfaces have moved from `org.apache.struts2.interceptor` to `org.apache.struts2.action`

| Old Package | New Package |
|------------|-------------|
| `org.apache.struts2.interceptor.ApplicationAware` | `org.apache.struts2.action.ApplicationAware` |
| `org.apache.struts2.interceptor.SessionAware` | `org.apache.struts2.action.SessionAware` |
| `org.apache.struts2.interceptor.ParameterAware` | `org.apache.struts2.action.ParameterAware` |
| `org.apache.struts2.interceptor.HttpParametersAware` | `org.apache.struts2.action.HttpParametersAware` |
| `org.apache.struts2.interceptor.ServletRequestAware` | `org.apache.struts2.action.ServletRequestAware` |
| `org.apache.struts2.interceptor.ServletResponseAware` | `org.apache.struts2.action.ServletResponseAware` |
| `org.apache.struts2.interceptor.PrincipalAware` | `org.apache.struts2.action.PrincipalAware` |
| `org.apache.struts2.interceptor.CookiesAware` | `org.apache.struts2.action.CookiesAware` |
| `org.apache.struts2.util.ServletContextAware` | `org.apache.struts2.action.ServletContextAware` |

**Example Fix:**
```java
// OLD (will not compile)
import org.apache.struts2.interceptor.SessionAware;

// NEW
import org.apache.struts2.action.SessionAware;
```

---

### 2. **Method Renames: set* → with***
**Impact:** HIGH - Will cause compilation errors

All `Aware` interface methods changed from `set*` to `with*`

| Old Method | New Method |
|-----------|------------|
| `setApplication(Map)` | `withApplication(Map)` |
| `setSession(Map)` | `withSession(Map)` |
| `setParameters(Map)` | `withParameters(Map)` |
| `setParameters(HttpParameters)` | `withParameters(HttpParameters)` |
| `setServletRequest(HttpServletRequest)` | `withServletRequest(HttpServletRequest)` |
| `setServletResponse(HttpServletResponse)` | `withServletResponse(HttpServletResponse)` |
| `setServletContext(ServletContext)` | `withServletContext(ServletContext)` |
| `setCookiesMap(Map)` | `withCookiesMap(Map)` |
| `setPrincipalProxy(PrincipalProxy)` | `withPrincipalProxy(PrincipalProxy)` |

**Example Fix:**
```java
// OLD
public class MyAction implements SessionAware {
    public void setSession(Map<String, Object> session) {
        this.session = session;
    }
}

// NEW
public class MyAction implements SessionAware {
    public void withSession(Map<String, Object> session) {
        this.session = session;
    }
}
```

---

## 🟡 IMPORTANT CHANGES (Require code modifications)

### 3. **File Upload Interceptor (Since Struts 6.4.0)**
**Impact:** MEDIUM - Deprecated in 6.4.0, removed in 7.0.0

`FileUploadInterceptor` is deprecated. Use `ActionFileUploadInterceptor` instead.

**Key Differences:**
- Old way: Used setter injection (`setFile()`, `setFileContentType()`, etc.)
- New way: Implements `org.apache.struts2.action.UploadedFilesAware` interface

**XML Configuration Change:**
```xml
<!-- OLD -->
<interceptor-ref name="fileUpload">
    <param name="maximumSize">500000</param>
</interceptor-ref>

<!-- NEW -->
<interceptor-ref name="actionFileUpload">
    <param name="maximumSize">500000</param>
</interceptor-ref>
```

**Java Code Change:**
```java
// OLD WAY (deprecated)
public class UploadAction extends ActionSupport {
    private File file;
    private String contentType;
    private String filename;
    
    public void setUpload(File file) { this.file = file; }
    public void setUploadContentType(String ct) { this.contentType = ct; }
    public void setUploadFileName(String fn) { this.filename = fn; }
}

// NEW WAY (recommended)
import org.apache.struts2.action.UploadedFilesAware;
import org.apache.struts2.action.UploadedFile;

public class UploadAction extends ActionSupport 
    implements UploadedFilesAware {
    
    private List<UploadedFile> uploadedFiles;
    
    @Override
    public void withUploadedFiles(List<UploadedFile> files) {
        this.uploadedFiles = files;
    }
}
```

---

### 4. **OpenSymphony Class Migrations**
**Impact:** MEDIUM - Some classes made abstract or replaced

| Old Class | New Class | Notes |
|-----------|-----------|-------|
| `com.opensymphony.xwork2.config.providers.XmlConfigurationProvider` | `org.apache.struts2.config.StrutsXmlConfigurationProvider` | Old one made abstract |
| `com.opensymphony.xwork2.conversion.TypeConversionException` | `org.apache.struts2.conversion.TypeConversionException` | Replaced |
| `com.opensymphony.xwork2.XWorkException` | `org.apache.struts2.StrutsException` | Replaced |

---

### 5. **FreeMarker Auto-Escaping (Since 6.0.0)**
**Impact:** MEDIUM - Template changes required

FreeMarker auto-escaping is enabled by default.

**Required Changes:**
- Remove manual `?html` escaping from FreeMarker templates
- Review all custom tags and templates

```ftl
<!-- OLD -->
${someValue?html}

<!-- NEW -->
${someValue}
```

---

### 6. **struts.xml DTD Update**
**Impact:** LOW - But should be updated

Update your `struts.xml` DOCTYPE declaration:

```xml
<!-- OLD (Struts 6.0) -->
<!DOCTYPE struts PUBLIC
    "-//Apache Software Foundation//DTD Struts Configuration 6.0//EN"
    "https://struts.apache.org/dtds/struts-6.0.dtd">

<!-- RECOMMENDED (Struts 6.7) -->
<!DOCTYPE struts PUBLIC
    "-//Apache Software Foundation//DTD Struts Configuration 6.0//EN"
    "https://struts.apache.org/dtds/struts-6.0.dtd">
```
*(DTD 6.0 is still valid for 6.7.x - no change needed unless you want latest)*

---

## 🟢 DEPRECATIONS (Still work but should be updated)

### 7. **com.opensymphony.xwork2 Package Deprecation (Since 6.7.0)**
**Impact:** LOW - Still works but deprecated

Many classes in `com.opensymphony.xwork2` package are deprecated and will be moved to `org.apache.struts2` in Struts 7.

**Recommendation:** Start migrating to new packages now to prepare for Struts 7.

---

### 8. **DWR and Sitemesh Plugins Dropped (Since 6.7.0)**
**Impact:** LOW - Only if you use these plugins

- **DWR Plugin**: Removed (no JakartaEE support)
- **Sitemesh Plugin**: Dropped, use direct integration instead

If using Sitemesh, integrate it directly. See: [sitemesh3 example](https://github.com/sitemesh/sitemesh3)

---

## ⚙️ SECURITY & BEHAVIOR CHANGES

### 9. **OGNL Expression Length Limit (Since 6.0.0)**
**Default:** 256 characters maximum

**To increase if needed:**
```xml
<struts>
    <constant name="struts.ognl.expressionMaxLength" value="512"/>
</struts>
```

---

### 10. **Multipart String Field Size Limit (Since 6.1.2.1)**
**Default:** 4096 bytes maximum for string fields in multipart requests

**To increase if needed:**
```xml
<struts>
    <constant name="struts.multipart.maxStringLength" value="10000"/>
</struts>
```

---

### 11. **Enum.values() Restriction (Since 6.6.0)**
**Impact:** MEDIUM - Security improvement

Cannot invoke static `Enum.values()` from OGNL expressions.

**Workaround:** Wrap it in a method on your Action class.

---

### 12. **Enhanced Proxy Detection (Since 6.6.0)**
**Impact:** LOW - Better security

Extended `SecurityMemberAccess` to detect Hibernate proxies.

---

## 📋 CHECKLIST FOR MIGRATION

- [ ] Update all `*Aware` interface imports from `org.apache.struts2.interceptor` to `org.apache.struts2.action`
- [ ] Rename all `set*` methods to `with*` in `Aware` implementations
- [ ] Replace `fileUpload` interceptor with `actionFileUpload` in struts.xml
- [ ] Update file upload actions to implement `UploadedFilesAware` instead of using setters
- [ ] Remove `?html` from FreeMarker templates
- [ ] Update `com.opensymphony.xwork2.*` class references
- [ ] Test all file upload functionality
- [ ] Review OGNL expression lengths
- [ ] Check if using DWR or Sitemesh plugins (need migration)
- [ ] Update Struts dependencies to 6.7.4
- [ ] Run comprehensive tests

---

## 🎯 RECOMMENDED APPROACH

1. **Use OpenRewrite recipe** (provided separately) to handle automatic migrations
2. **Manually review and fix**:
   - File upload implementations
   - FreeMarker templates
   - Any custom interceptors
3. **Test thoroughly** in a development environment
4. **Check logs** for deprecation warnings
5. **Update documentation** for your team

---

## 📚 REFERENCES

- [Struts 2.5 to 6.0.0 Migration Guide](https://cwiki.apache.org/confluence/display/WW/Struts+2.5+to+6.0.0+migration)
- [Version Notes 6.4.0](https://cwiki.apache.org/confluence/display/WW/Version+Notes+6.4.0)
- [Version Notes 6.6.0](https://cwiki.apache.org/confluence/display/WW/Version+Notes+6.6.0)
- [Version Notes 6.7.0](https://cwiki.apache.org/confluence/display/WW/Version+Notes+6.7.0)
- [Action File Upload Interceptor](https://struts.apache.org/core-developers/action-file-upload-interceptor)

---

## ⚠️ IMPORTANT NOTES

1. **Struts 6.7.4** is the latest stable Java 8 compatible version
2. **Struts 6.8.0** has security vulnerability S2-068 - **DO NOT USE**
3. **Struts 7.x** requires Java 17+ and JakartaEE
4. All 6.x versions require **Servlet API 3.1+**, **JSP API 2.1+**, and **Java 8+**
