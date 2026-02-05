 Membership
Canonical write path	Implementing files
clinics/{clinicId}/members/{uid}	functions/src/clinic/acceptInvite.ts, functions/src/clinic/createClinic.ts (legacy mirror), functions/src/clinic/setMembershipStatus.ts (merge), functions/src/clinic/settings/provisionClinicDefaults.ts, functions/src/clinic/onClinicCreatedProvisionOwner.ts (legacy mirror), functions/src/clinic/updateMemberProfile.ts, functions/src/clinic/updateClinicProfile.ts
clinics/{clinicId}/memberships/{uid}	functions/src/clinic/createClinic.ts, functions/src/clinic/acceptInvite.ts (legacy mirror), functions/src/clinic/onClinicCreatedProvisionOwner.ts, functions/src/clinic/setMembershipStatus.ts, functions/src/clinic/staff/setStaffAvailabilityDefault.ts, functions/src/clinic/staff/upsertStaffProfile.ts, functions/src/clinic/updateMemberProfile.ts, functions/src/clinic/updateClinicProfile.ts, functions/src/clinic/syncMyDisplayName.ts, functions/src/clinic/bootstrapPublicBookingSettings.ts
users/{uid}/memberships/{clinicId}	functions/src/clinic/createClinic.ts, functions/src/clinic/acceptInvite.ts, functions/src/clinic/onClinicCreatedProvisionOwner.ts, functions/src/clinic/settings/provisionClinicDefaults.ts
clinics/{clinicId}/invites/{inviteId}	functions/src/clinic/inviteMember.ts (create), functions/src/clinic/acceptInvite.ts (update status)
2. Appointments
Canonical write path	Implementing files
clinics/{clinicId}/appointments/{appointmentId}	Create: functions/src/clinic/appointments/createAppointmentInternal.ts (used by createAppointment.ts, functions/src/clinic/booking/onBookingRequestCreate.ts, functions/src/public/createPublicBooking.ts). Update: functions/src/clinic/updateAppointment.ts, functions/src/clinic/updateAppointmentStatus.ts, functions/src/public/bookingActions.ts. Delete: functions/src/clinic/deleteAppointment.ts.
3. Intake submit
Canonical write path	Implementing files
clinics/{clinicId}/intakeSessions/{sessionId}	functions/src/clinic/intake/submitIntakeSession.ts
clinics/{clinicId}/intakeInvites/{inviteId}	functions/src/clinic/intake/submitIntakeSession.ts (writes usedAt, submittedSessionId when submit is tied to an invite)
Callables / triggers that drive these writes
Membership: inviteMember (invites), acceptInvite (members + user index + invite status); createClinic (clinic + members + memberships + user index); setMembershipStatus; onClinicCreatedProvisionOwner (memberships + members + user index); provisionClinicDefaults (members + user index when missing); plus update flows above.
Appointments: createAppointment, createPublicBooking, and onBookingRequestCreate → createAppointmentInternal; updateAppointment, updateAppointmentStatus, bookingActions (reschedule/cancel); deleteAppointment.
Intake submit: submitIntakeSessionFn → submitIntakeSession.ts (intakeSessions + optional intakeInvites update).