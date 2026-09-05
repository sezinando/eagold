//+------------------------------------------------------------------+
//|                                                   EAGOLD.mq4     |
//|                         EAGOLD - Expert Advisor for MT4          |
//+------------------------------------------------------------------+
#property strict
#property version   "0.1.1"
#property description "Initial EAGOLD EA skeleton - Git pull test."

input int MagicNumber = 1001;
input double Lots = 0.01;

int OnInit()
  {
   Print("EAGOLD initialized. MagicNumber=", MagicNumber,
         " Lots=", DoubleToString(Lots, 2));
   Print("EAGOLD v0.1.1 - GitHub pull test successful.");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   Print("EAGOLD deinitialized. Reason=", reason);
  }

void OnTick()
  {
   // Strategy engine will be implemented in subsequent versions.
  }
//+------------------------------------------------------------------+
