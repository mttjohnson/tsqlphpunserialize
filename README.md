# tsqlphpunserialize
Unserialize PHP serialized data in T-SQL

I am trying to extract a gift card code from a Magento order. Some other code uses the Magento API to retrieve the order info as XML from Magento and insert the XML into a MS SQL Server record. Using T-SQL I can use XML functions to parse the XML that was retrieved from the Magento API and get almost everything I need, but the only place the actual gift card code is stored is in the gift_cards field which happens to be a php serialized string.

Examples:
a:1:{i:0;a:5:{s:1:"i";s:1:"1";s:1:"c";s:12:"00XCY8S3ZXCU";s:1:"a";d:119;s:2:"ba";d:119;s:10:"authorized";d:119;}}
a:3:{i:0;a:5:{s:1:"i";s:2:"10";s:1:"c";s:12:"045EMJJWRCF1";s:1:"a";d:100;s:2:"ba";d:100;s:10:"authorized";d:100;}i:1;a:5:{s:1:"i";s:2:"11";s:1:"c";s:12:"06DUQ7Z5GVT7";s:1:"a";d:101;s:2:"ba";d:101;s:10:"authorized";d:101;}i:2;a:5:{s:1:"i";s:2:"12";s:1:"c";s:12:"07A6MRYW511J";s:1:"a";d:102;s:2:"ba";d:102;s:10:"authorized";d:102;}}

The gift card code is the value in the array with the key of “c” such as:
00XCY8S3ZXCU 045EMJJWRCF1 06DUQ7Z5GVT7 07A6MRYW511J

I’m currently trying to tackle this by parsing the value using a T-SQL function, which is like trying to drive a nail with a screw driver. Apparently this has been asked before here and the only suggestion was to build a parser from scratch in T-SQL, but that using PHP to unserialize it was the better option.

It would be nice if Magento didn’t store PHP serialized data in their database, and then serve it out still serialized in their web services, but that’s what I have to work with. I would consider using C# to convert it and store it as a separate field in the database, but it would be a lot more convenient to be able to parse the data in T-SQL. If I were to use C# to parse and unserialize the PHP object I’d probably store it as XML back in the database because that’s a much better format to exchange the data in.


This is what I was able to come up with myself. I was encouraged by a post about parsing JSON and decided to figure it out for serialized php objects. I took a completely different approach though.

The serialized php string:
a:3:{
i:0;
a:5:{
s:1:"i";
s:2:"10";
s:1:"c";
s:12:"045EMJJWRCF1";
s:1:"a";
d:100;
s:2:"ba";
d:100;
s:10:"authorized";
d:100;
}
i:1;
a:5:{
s:1:"i";
s:2:"11";
s:1:"c";
s:12:"06DUQ7Z5GVT7";
s:1:"a";
d:101;
s:2:"ba";
d:101;
s:10:"authorized";
d:101;
}
i:2;
a:5:{
s:1:"i";
s:2:"12";
s:1:"c";
s:12:"07A6MRYW511J";
s:1:"a";
d:102;
s:2:"ba";
d:102;
s:10:"authorized";
d:102;
}
}

My query to get the results:
select *
from fnParsePhpSerializedString('a:3:{i:0;a:5:{s:1:"i";s:2:"10";s:1:"c";s:12:"045EMJJWRCF1";s:1:"a";d:100;s:2:"ba";d:100;s:10:"authorized";d:100;}i:1;a:5:{s:1:"i";s:2:"11";s:1:"c";s:12:"06DUQ7Z5GVT7";s:1:"a";d:101;s:2:"ba";d:101;s:10:"authorized";d:101;}i:2;a:5:{s:1:"i";s:2:"12";s:1:"c";s:12:"07A6MRYW511J";s:1:"a";d:102;s:2:"ba";d:102;s:10:"authorized";d:102;}}')

The results of the query:
element_id parent_id var_name var_type var_length value_int value_string value_decimal
----------- ----------- -------------------------------------------------- -------------------------------------------------- ----------- ----------- ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- ---------------------------------------
1 0 NULL a 3 NULL NULL NULL
2 1 0 a 5 NULL NULL NULL
3 1 1 a 5 NULL NULL NULL
4 1 2 a 5 NULL NULL NULL
5 2 i s 2 NULL 10 NULL
6 2 c s 12 NULL 045EMJJWRCF1 NULL
7 2 a d NULL NULL NULL 100
8 2 ba d NULL NULL NULL 100
9 2 authorized d NULL NULL NULL 100
10 3 i s 2 NULL 11 NULL
11 3 c s 12 NULL 06DUQ7Z5GVT7 NULL
12 3 a d NULL NULL NULL 101
13 3 ba d NULL NULL NULL 101
14 3 authorized d NULL NULL NULL 101
15 4 i s 2 NULL 12 NULL
16 4 c s 12 NULL 07A6MRYW511J NULL
17 4 a d NULL NULL NULL 102
18 4 ba d NULL NULL NULL 102
19 4 authorized d NULL NULL NULL 102

If I just wanted the gift card codes I can write a query like this:
select value_string
from fnParsePhpSerializedString('a:3:{i:0;a:5:{s:1:"i";s:2:"10";s:1:"c";s:12:"045EMJJWRCF1";s:1:"a";d:100;s:2:"ba";d:100;s:10:"authorized";d:100;}i:1;a:5:{s:1:"i";s:2:"11";s:1:"c";s:12:"06DUQ7Z5GVT7";s:1:"a";d:101;s:2:"ba";d:101;s:10:"authorized";d:101;}i:2;a:5:{s:1:"i";s:2:"12";s:1:"c";s:12:"07A6MRYW511J";s:1:"a";d:102;s:2:"ba";d:102;s:10:"authorized";d:102;}}')
where parent_id != 0 and
var_name = 'c'

Results:
value_string
-------------
045EMJJWRCF1
06DUQ7Z5GVT7
07A6MRYW511J

Here is the T-SQL function for parsing the serialized PHP string:

fnParsePhpSerializedString.sql

And though it doesn't account for all serialized types and such, it was enough for my purpose here, and the included comments should help to guide anyone that needs to adapt it for their own use, or extend it's functionality.
