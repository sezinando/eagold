//==================================================================
// EAGOLD — TRIAL / LICENSE EXPIRATION RESOURCE
//==================================================================
// This file intentionally contains NO input variables.
// Edit the date below before building a customer trial package.
//
// IMPORTANT:
// - This is a source-code license gate, not an MT4 input.
// - When expired, the EA should refuse new trading operations.
// - Existing positions should NOT be force-closed solely because
//   the trial expired; normal risk management remains responsible.
//==================================================================

#ifndef __EAGOLD_LICENSE_MQH__
#define __EAGOLD_LICENSE_MQH__

//==================================================================
// EDIT THIS DATE IN THE SOURCE CODE FOR EACH TRIAL PACKAGE.
// Example: D'2026.12.31 23:59:59'
//==================================================================
const datetime EAGOLD_EXPIRATION_DATE = D'2026.12.31 23:59:59';

bool EAGOLD_IsExpired()
{
   return(TimeCurrent() > EAGOLD_EXPIRATION_DATE);
}

string EAGOLD_ExpirationText()
{
   return(TimeToString(EAGOLD_EXPIRATION_DATE,TIME_DATE|TIME_SECONDS));
}

void EAGOLD_LogExpiration()
{
   static bool logged=false;
   if(logged) return;
   logged=true;

   Print("EAGOLD LICENSE EXPIRED | Expiration=",
         EAGOLD_ExpirationText(),
         " | Trading disabled.");
}

#endif
