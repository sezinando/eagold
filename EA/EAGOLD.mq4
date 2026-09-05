//+------------------------------------------------------------------+
//|                                                   EAGOLD.mq4     |
//|                         EAGOLD - Expert Advisor for MT4          |
//+------------------------------------------------------------------+
#property strict
#property version   "0.1.2"
#property description "Initial EAGOLD EA skeleton - Git pull test v2."

input int MagicNumber = 1001;
input double Lots = 0.01;

int OnInit()
  {
   Print("==================================================");
   Print("EAGOLD v0.1.2 INITIALIZED");
   Print("GitHub -> git pull integration test #2 OK");
   Print("MagicNumber=", MagicNumber,
         " Lots=", DoubleToString(Lots, 2));
   Print("==================================================");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   Print("EAGOLD v0.1.2 deinitialized. Reason=", reason);
  }

void OnTick()
  {
   // Strategy engine will be implemented in subsequent versions.
  }
//+------------------------------------------------------------------+
