# RideMate Final Testing Checklist

## Auth
- [ ] Passenger signup works
- [ ] Driver signup works
- [ ] Login/logout works
- [ ] Admin role assigned by SQL works
- [ ] Suspended user cannot continue critical actions

## Passenger
- [ ] Passenger can search rides
- [ ] Passenger can filter safe matching rides
- [ ] Male passenger cannot book female-only ride
- [ ] Female passenger cannot book male-only ride
- [ ] Solo passenger cannot book family-only ride
- [ ] Family profile can book family-only ride
- [ ] Passenger cannot book own ride
- [ ] Duplicate booking is blocked
- [ ] Passenger can cancel pending/accepted booking
- [ ] Phone number is hidden before accepted status
- [ ] Contact button works after accepted status

## Driver
- [ ] Driver can add vehicle
- [ ] Driver can post ride
- [ ] Driver can post mixed/male/female/family passenger rule
- [ ] Driver can see pending requests
- [ ] Driver can accept request
- [ ] Driver can reject request
- [ ] Driver can close ride
- [ ] Driver cannot accept more seats than available

## Concurrency
- [ ] Create ride with 1 seat
- [ ] Login as two passengers in two browsers
- [ ] Send two booking requests
- [ ] Accept first request
- [ ] Try accepting second request
- [ ] Second request should fail with no seats available

## Admin
- [ ] Admin dashboard shows KPIs
- [ ] Admin can view users
- [ ] Admin can view rides
- [ ] Admin can view reports
- [ ] Admin can mark report resolved

## Safety
- [ ] Report form submits
- [ ] Police/support buttons open phone dialer on mobile
- [ ] Driver gender visible before booking
- [ ] Vehicle plate visible before booking

## Deployment
- [ ] Netlify build succeeds
- [ ] Environment variables are set
- [ ] Site does not show setup error
- [ ] Refresh on internal route does not 404
- [ ] PWA install prompt appears on supported devices
