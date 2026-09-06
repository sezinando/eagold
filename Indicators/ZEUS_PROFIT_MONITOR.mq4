#property strict
#property indicator_chart_window
#property indicator_buffers 0
#property version   "0.001"
#property description "ZEUS ProfitB/ProfitS monitor - tick snapshots and order events"

// ============================================================================
// ZEUS_PROFIT_MONITOR v0.001
//
// Objective:
//   Reconstruct the displayed ZEUS ProfitB / ProfitS values from MT4 orders,
//   record them on every tick, and create an event log that can be crossed
//   with MT4 order history later.
//
// IMPORTANT:
//   An external indicator cannot read a local variable declared inside another
//   EA. Therefore ProfitB and ProfitS below are reconstructed from the open
//   market orders visible to the terminal. With the display shown by ZEUS,
//   ProfitB = sum of BUY OrderProfit() and ProfitS = sum of SELL OrderProfit().
// ============================================================================

input int    MagicNumber       = -1;     // -1 = all magic numbers
input string SnapshotFile     = "ZEUS_PROFIT_MONITOR_SNAPSHOT.csv";
input string EventsFile       = "ZEUS_PROFIT_MONITOR_EVENTS.csv";
input bool   IncludePending   = true;
input bool   WriteEveryTick   = true;
input bool   LogOrderEvents   = true;
input bool   LogHistoryEvents = true;

string PREFIX = "ZEUS_MONITOR";

struct OrderState
{
   int      ticket;
   int      type;
   double   lots;
   double   openPrice;
   datetime openTime;
};

OrderState PreviousOrders[];
bool InitializedState = false;

bool IsSelectedOrderInScope()
{
   if(OrderSymbol() != Symbol()) return(false);
   if(MagicNumber >= 0 && OrderMagicNumber() != MagicNumber) return(false);
   int type = OrderType();
   if(type == OP_BUY || type == OP_SELL) return(true);
   if(IncludePending && (type == OP_BUYSTOP || type == OP_SELLSTOP || type == OP_BUYLIMIT || type == OP_SELLLIMIT)) return(true);
   return(false);
}

string TypeName(int type)
{
   if(type == OP_BUY)       return("BUY");
   if(type == OP_SELL)      return("SELL");
   if(type == OP_BUYSTOP)   return("BUYSTOP");
   if(type == OP_SELLSTOP)  return("SELLSTOP");
   if(type == OP_BUYLIMIT)  return("BUYLIMIT");
   if(type == OP_SELLLIMIT) return("SELLLIMIT");
   return("UNKNOWN");
}

string TimeText(datetime value)
{
   if(value <= 0) return("");
   return(TimeToString(value, TIME_DATE|TIME_SECONDS));
}

bool SameState(OrderState &a, OrderState &b)
{
   if(a.ticket != b.ticket) return(false);
   if(a.type != b.type) return(false);
   if(MathAbs(a.lots - b.lots) > 0.0000001) return(false);
   if(MathAbs(a.openPrice - b.openPrice) > Point * 0.1) return(false);
   if(a.openTime != b.openTime) return(false);
   return(true);
}

int FindPreviousTicket(int ticket)
{
   for(int i=0; i<ArraySize(PreviousOrders); i++)
      if(PreviousOrders[i].ticket == ticket) return(i);
   return(-1);
}

void EnsureSnapshotHeader()
{
   int handle = FileOpen(SnapshotFile, FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE, ';');
   if(handle == INVALID_HANDLE)
   {
      Print(PREFIX, " cannot open snapshot file. error=", GetLastError());
      return;
   }
   if(FileSize(handle) == 0)
   {
      FileWrite(handle,
         "server_time","local_time","symbol","bid","ask","spread_points",
         "profitB","profitS","profit_total","buy_count","sell_count",
         "buy_lots","sell_lots","pending_count","balance","equity","free_margin");
   }
   FileClose(handle);
}

void EnsureEventsHeader()
{
   int handle = FileOpen(EventsFile, FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE, ';');
   if(handle == INVALID_HANDLE)
   {
      Print(PREFIX, " cannot open events file. error=", GetLastError());
      return;
   }
   if(FileSize(handle) == 0)
   {
      FileWrite(handle,
         "event_time","event_type","ticket","type","symbol","magic",
         "lots","open_price","open_time","close_price","close_time",
         "profit","swap","commission","comment","profitB","profitS","profit_total");
   }
   FileClose(handle);
}

void CalculateProfit(double &profitB, double &profitS, double &profitTotal,
                    int &buyCount, int &sellCount, double &buyLots, double &sellLots,
                    int &pendingCount)
{
   profitB = 0.0;
   profitS = 0.0;
   profitTotal = 0.0;
   buyCount = 0;
   sellCount = 0;
   buyLots = 0.0;
   sellLots = 0.0;
   pendingCount = 0;

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsSelectedOrderInScope()) continue;

      int type = OrderType();
      if(type == OP_BUY)
      {
         buyCount++;
         buyLots += OrderLots();
         profitB += OrderProfit();
      }
      else if(type == OP_SELL)
      {
         sellCount++;
         sellLots += OrderLots();
         profitS += OrderProfit();
      }
      else
      {
         pendingCount++;
      }
   }

   profitTotal = profitB + profitS;
}

void WriteSnapshot()
{
   double profitB, profitS, profitTotal, buyLots, sellLots;
   int buyCount, sellCount, pendingCount;
   CalculateProfit(profitB, profitS, profitTotal, buyCount, sellCount, buyLots, sellLots, pendingCount);

   RefreshRates();
   int handle = FileOpen(SnapshotFile, FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE, ';');
   if(handle == INVALID_HANDLE)
   {
      Print(PREFIX, " snapshot write failed. error=", GetLastError());
      return;
   }
   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle,
      TimeText(TimeCurrent()),
      TimeText(TimeLocal()),
      Symbol(),
      DoubleToString(Bid, Digits),
      DoubleToString(Ask, Digits),
      DoubleToString((Ask-Bid)/Point, 1),
      DoubleToString(profitB, 2),
      DoubleToString(profitS, 2),
      DoubleToString(profitTotal, 2),
      buyCount,
      sellCount,
      DoubleToString(buyLots, 2),
      DoubleToString(sellLots, 2),
      pendingCount,
      DoubleToString(AccountBalance(), 2),
      DoubleToString(AccountEquity(), 2),
      DoubleToString(AccountFreeMargin(), 2));
   FileClose(handle);
}

void WriteEvent(string eventType, int ticket, int type, double lots, double openPrice,
                datetime openTime, double closePrice, datetime closeTime,
                double profit, double swap, double commission, string comment,
                double profitB, double profitS, double profitTotal)
{
   int handle = FileOpen(EventsFile, FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE, ';');
   if(handle == INVALID_HANDLE)
   {
      Print(PREFIX, " event write failed. error=", GetLastError());
      return;
   }
   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle,
      TimeText(TimeCurrent()),
      eventType,
      ticket,
      TypeName(type),
      Symbol(),
      MagicNumber,
      DoubleToString(lots, 2),
      DoubleToString(openPrice, Digits),
      TimeText(openTime),
      DoubleToString(closePrice, Digits),
      TimeText(closeTime),
      DoubleToString(profit, 2),
      DoubleToString(swap, 2),
      DoubleToString(commission, 2),
      comment,
      DoubleToString(profitB, 2),
      DoubleToString(profitS, 2),
      DoubleToString(profitTotal, 2));
   FileClose(handle);
}

void ScanCurrentOrderEvents(double profitB, double profitS, double profitTotal)
{
   if(!LogOrderEvents) return;

   OrderState CurrentOrders[];
   ArrayResize(CurrentOrders, 0);

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsSelectedOrderInScope()) continue;

      int n = ArraySize(CurrentOrders);
      ArrayResize(CurrentOrders, n+1);
      CurrentOrders[n].ticket = OrderTicket();
      CurrentOrders[n].type = OrderType();
      CurrentOrders[n].lots = OrderLots();
      CurrentOrders[n].openPrice = OrderOpenPrice();
      CurrentOrders[n].openTime = OrderOpenTime();
   }

   if(!InitializedState)
   {
      // Existing orders are recorded with their real OrderOpenTime. This lets
      // the resulting event file be crossed against MT4 history even when the
      // indicator is attached after ZEUS has already opened the order.
      for(int c=0; c<ArraySize(CurrentOrders); c++)
      {
         int idx = FindPreviousTicket(CurrentOrders[c].ticket);
         if(idx >= 0) continue;
         if(OrderSelect(CurrentOrders[c].ticket, SELECT_BY_TICKET, MODE_TRADES))
         {
            WriteEvent("OPEN_EXISTING", CurrentOrders[c].ticket, CurrentOrders[c].type,
               CurrentOrders[c].lots, CurrentOrders[c].openPrice, CurrentOrders[c].openTime,
               0.0, 0, 0.0, 0.0, 0.0, OrderComment(),
               profitB, profitS, profitTotal);
         }
      }
      ArrayCopy(PreviousOrders, CurrentOrders);
      InitializedState = true;
      return;
   }

   // New orders / activation changes.
   for(int c=0; c<ArraySize(CurrentOrders); c++)
   {
      int previous = FindPreviousTicket(CurrentOrders[c].ticket);
      if(previous >= 0)
      {
         if(SameState(CurrentOrders[c], PreviousOrders[previous])) continue;

         if(OrderSelect(CurrentOrders[c].ticket, SELECT_BY_TICKET, MODE_TRADES))
         {
            WriteEvent("MODIFIED", CurrentOrders[c].ticket, CurrentOrders[c].type,
               CurrentOrders[c].lots, CurrentOrders[c].openPrice, CurrentOrders[c].openTime,
               0.0, 0, 0.0, 0.0, 0.0, OrderComment(),
               profitB, profitS, profitTotal);
         }
      }
      else if(OrderSelect(CurrentOrders[c].ticket, SELECT_BY_TICKET, MODE_TRADES))
      {
         WriteEvent("OPEN_OR_ACTIVATED", CurrentOrders[c].ticket, CurrentOrders[c].type,
            CurrentOrders[c].lots, CurrentOrders[c].openPrice, CurrentOrders[c].openTime,
            0.0, 0, 0.0, 0.0, 0.0, OrderComment(),
            profitB, profitS, profitTotal);
      }
   }

   // Orders no longer present are checked in history. This identifies closes
   // and also preserves the actual close time and realized result.
   for(int p=0; p<ArraySize(PreviousOrders); p++)
   {
      int current = -1;
      for(int c=0; c<ArraySize(CurrentOrders); c++)
         if(CurrentOrders[c].ticket == PreviousOrders[p].ticket) { current = c; break; }
      if(current >= 0) continue;

      if(OrderSelect(PreviousOrders[p].ticket, SELECT_BY_TICKET, MODE_HISTORY))
      {
         int type = OrderType();
         if(type == OP_BUY || type == OP_SELL || IncludePending)
         {
            double realized = OrderProfit() + OrderSwap() + OrderCommission();
            WriteEvent("CLOSED_OR_DELETED", OrderTicket(), type,
               OrderLots(), OrderOpenPrice(), OrderOpenTime(), OrderClosePrice(),
               OrderCloseTime(), realized, OrderSwap(), OrderCommission(), OrderComment(),
               profitB, profitS, profitTotal);
         }
      }
   }

   ArrayCopy(PreviousOrders, CurrentOrders);
}

void ScanHistoryForNewClosures(double profitB, double profitS, double profitTotal)
{
   if(!LogHistoryEvents) return;
   // The normal state transition scanner already catches orders disappearing
   // from MODE_TRADES. This function intentionally does not duplicate history
   // rows; it exists as a clear separation point for future history analysis.
}

int OnInit()
{
   EnsureSnapshotHeader();
   EnsureEventsHeader();
   Print(PREFIX, " initialized. Snapshot=", SnapshotFile, " Events=", EventsFile,
         " MagicNumber=", MagicNumber, " WriteEveryTick=", WriteEveryTick);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Print(PREFIX, " stopped. reason=", reason);
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   double profitB, profitS, profitTotal, buyLots, sellLots;
   int buyCount, sellCount, pendingCount;
   CalculateProfit(profitB, profitS, profitTotal, buyCount, sellCount, buyLots, sellLots, pendingCount);

   if(WriteEveryTick)
      WriteSnapshot();

   ScanCurrentOrderEvents(profitB, profitS, profitTotal);
   ScanHistoryForNewClosures(profitB, profitS, profitTotal);

   return(rates_total);
}
