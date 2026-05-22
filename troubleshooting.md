##  Issue 1: npm ci fails inside Docker — peer dependency conflicts

```bash
npm error Invalid: lock file's @babel/core@7.12.3 does not satisfy @babel/core@7.29.0
npm warn ERESOLVE overriding peer dependency
npm warn Found: postcss@7.0.39
npm warn Conflicting peer dependency: postcss@8.5.15

```

**cause**: This project uses older packages (postcss@7, tailwindcss) that have peer dependency conflicts with newer npm versions. The lock file generated locally with npm v24 cannot be cleanly resolved inside the Node 18 Docker container.

**fix**: add --legacy-peer-deps flag in Dockerfile:

```dockerfile
	RUN npm ci --legacy-peer-deps
```

***why this is safe**: --legacy-peer-deps tells npm to ignore peer dependency conflicts and install packages using the old npm v6 resolution behavior. This is acceptable for a demo/learning project.

## Issue 5: ERR_OSSL_EVP_UNSUPPORTED inside Docker during `npm run build`

**Cause:**
The `export NODE_OPTIONS` fix only applies to your local shell session.
Inside Docker, it has no effect — you need to set it via ENV in the Dockerfile.

**Fix:**
ENV NODE_OPTIONS=--openssl-legacy-provider

### finally 

 then i researched about why these issue , i found it is beacuse of the node verison mismatch issue .
 and use node v 18. and it worked fine.


result: containeration done with reduced image size to 63 mb.

