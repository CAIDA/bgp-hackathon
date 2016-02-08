Rather than duplicate the entire code tree here, all of the code that was
written for the hackathon (plus commit logs etc.) can be found at: 

https://github.com/salcock/bgpstream/tree/filterparser

Summary of what was achieved:

 * Replaced awkward filtering scheme with a system based on providing a single
   filter string, similar to how BPF is used to filter packets. This means
   that libbgpstream users won't need to write pages of filter creation code
   and bgpreader users won't need to remember 20 different command line flags.

 * Added ability to filter elements based on a number of new parameters:
      IP version of prefix
      Element type (withdrawal, announcement, etc)
      Exact Prefix Match
      Less Specific Prefix Match
      More Specific Prefix Match (technically already present :) )
      AS Path

 * AS Path filters accept regular expressions, using the syntax published by
   Cisco (http://www.cisco.com/c/en/us/support/docs/ip/border-gateway-protocol-bgp/13754-26.html),
   including support for special characters '^', '$', and underscore.

   AS Path regexs can also be preceded by a '!' to negate the following
   expression, i.e. only match if the path does NOT contain this segment,
   which is an extension beyond the Cisco standard.

 * Added ability to specify a time filter using a time period relative to
   the current time, e.g. if the time filter is specified as '3 h', BGPStream
   will fetch the most recent 3 hours of BGP data. Time periods can be
   expressed in seconds, minutes, hours or days.
   
 * Updated pybgpstream to also use the new filtering API, so Python users
   aren't left out!

 * Updated bgpreader to include options for a filter string and an interval
   string.

      
      
